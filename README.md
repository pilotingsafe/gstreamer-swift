# GStreamer

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![CI](https://github.com/pilotingsafe/gstreamer-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/pilotingsafe/gstreamer-swift/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20Linux-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A Swift 6.2 package that wraps GStreamer with low-level Swift APIs and selected
concurrency-friendly helpers.

## Features

### Core v0.1 Surface

- Low-level `Pipeline`, `Element`, and `Bus` wrappers around GStreamer primitives
- `AppSink` and `AppSource` helpers for pulling frames and pushing data
- `Buffer`, `AudioBuffer`, and `VideoFrame` access through lifetime-bound `RawSpan`
- Swift Concurrency sequences for bus messages, frames, and buffers

### Convenience and Experimental Layers

- Typed pipeline builders for composable video pipeline construction
- Explicit packet-delivery contracts for realtime best-effort and reliable streams
- Convenience builders for common audio/video source and sink workflows

For the exact v0.1 release scope and known limitations, see
[RELEASE.md](RELEASE.md) and [docs/v0.1-scope.md](docs/v0.1-scope.md).

## Requirements

- Swift 6.2+
- v0.1 documentation and verification focus on macOS and Linux
- GitHub Actions CI runs Swift 6.2.4 on ubuntu-22.04 and macos-26 (arm64)
  with GStreamer system dependencies installed
- `Package.swift` declares Apple platform minimums for macOS, iOS, tvOS,
  watchOS, and visionOS 26.0; those declarations are not the same as CI-tested
  v0.1 support
- `pkgconf`/`pkg-config` available on PATH
- GStreamer 1.20+ development headers and libraries installed on your system
- `pkg-config` metadata for the SwiftPM system-library targets:
  `gstreamer-1.0`, `gstreamer-app-1.0`, and `gstreamer-video-1.0`

### Installing GStreamer

**macOS (Homebrew):**
```bash
brew install pkgconf gstreamer
```

This installs `pkg-config`, GStreamer, the base development files, and common plugins. Verify with:
```bash
gst-inspect-1.0 --version
```

**Ubuntu/Debian:**
```bash
# Core development libraries
sudo apt install \
    pkg-config \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

# Runtime plugins (recommended)
sudo apt install \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly

# For video support
sudo apt install gstreamer1.0-libav

# For hardware acceleration (optional)
sudo apt install gstreamer1.0-vaapi
```

**Verifying Installation:**
```bash
gst-inspect-1.0 --version
# Should output: gst-inspect-1.0 version 1.x.x
```

**SwiftPM Preflight:**

Run this before `swift build` or `swift test` to confirm SwiftPM can find all system-library targets:
```bash
pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0
```

Print the resolved versions with:
```bash
pkg-config --modversion gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0
```

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pilotingsafe/gstreamer-swift.git", branch: "main")
]
```

After a v0.1 tag exists, prefer:

```swift
dependencies: [
    .package(url: "https://github.com/pilotingsafe/gstreamer-swift.git", from: "0.1.0")
]
```

Then add `GStreamer` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["GStreamer"]
)
```

## Usage

### Basic Pipeline

```swift
import GStreamer

// Create and run a pipeline.
let pipeline = try Pipeline("videotestsrc num-buffers=100 ! autovideosink")
try pipeline.play()

// Own bus draining with one sequence.
messageLoop: for await message in pipeline.bus.messageSequence(filter: [.eos, .error]) {
    switch message {
    case .eos:
        break messageLoop
    case .error(let message, let debug):
        print("Error: \(message)")
        if let debug { print("Debug: \(debug)") }
        break messageLoop
    default:
        break
    }
}

pipeline.stop()
```

`messageSequence(filter:)` is a single-owner async sequence backed by a private
GStreamer bus watch. Creating an iterator starts the watch, which can drain and
buffer matching `BusMessage` values before the consumer awaits `next()`. That
parsed-message buffer currently holds at most 256 parsed messages and uses
best-effort overflow handling: ERROR and EOS are critical, older
noncritical messages are discarded first, and a newest critical message remains
observable even if older critical messages must be evicted. EOS and ERROR are
delivered as values so the caller decides when to break.

`messages(filter:)` remains the stream-based compatibility API. It uses a
detached producer task and an `AsyncStream`, finishes after delivering EOS, and
continues to back the `errors()`, `warnings()`, and `stateChanges()`
convenience streams. The EOS waiting helpers use `messageSequence(filter:)` and
inherit its single-owner bus-draining behavior. Do not run multiple bus
consumers unless you intend them to compete for the same destructive GStreamer
bus queue. See the DocC article `APIContract` for the consolidated lifecycle,
bus, and packet-delivery contract.

### Pulling Video Frames

```swift
import GStreamer

let pipeline = try Pipeline("""
    videotestsrc num-buffers=10 ! \
    video/x-raw,format=BGRA,width=640,height=480 ! \
    appsink name=sink
    """)

let sink = try AppSink(pipeline: pipeline, name: "sink")
try pipeline.play()

for await frame in sink.frames() {
    print("Frame: \(frame.width)x\(frame.height) \(frame.format.formatString)")

    try frame.withUnsafeBytes { buffer in
        let firstPixel = Array(buffer.prefix(4))
        print("First pixel: \(firstPixel)")
    }
}

pipeline.stop()
```

### Pushing Data With AppSource

```swift
import GStreamer

let pipeline = try Pipeline("""
    appsrc name=src ! \
    audio/x-raw,format=S16LE,rate=44100,channels=2,layout=interleaved ! \
    audioconvert ! fakesink
    """)

let src = try AppSource(pipeline: pipeline, name: "src")
src.setCaps("audio/x-raw,format=S16LE,rate=44100,channels=2,layout=interleaved")

try pipeline.play()
try src.push(data: [0, 0, 0, 0], pts: 0, duration: 22_675_736)
src.endOfStream()
pipeline.stop()
```

### Buffer Access

```swift
import GStreamer

for await frame in sink.frames() {
    let bytes = frame.bytes
    print("Frame byte count: \(bytes.byteCount)")

    try frame.withUnsafeBytes { buffer in
        // Use this scoped pointer when an interop API needs UnsafeRawBufferPointer.
    }
}
```

### Type-Safe Pipelines

Status: the typed pipeline DSL is an experimental, non-core v0.1 convenience
layer. The low-level `Pipeline`, `Element`, and appsink/appsrc APIs above are
the stable foundation for direct GStreamer work.

```swift
@VideoPipelineBuilder
func pipeline() -> PartialPipeline<_VideoFrame<BGRA<640, 480>>> {
    VideoTestSource()
    VideoConvert()
    RawVideoFormat(layout: BGRA<640, 480>.self, framerate: "30/1")
}

try await withPipeline {
    pipeline()
} withEachFrame: { frame in
    let raw = frame.rawFrame
    print("\(raw.width)x\(raw.height) \(raw.format)")
}
```

## Convenience APIs

Status: source and sink builders are non-core v0.1 convenience layers over the
lower-level wrappers. Use them when their platform/plugin choices fit your
application; use manual `Pipeline` construction when you need direct GStreamer
control.

The source and sink builders compose common pipeline fragments for application
code. They are convenience APIs layered over the lower-level wrappers above, and
their backend availability depends on platform and installed GStreamer plugins.

### Video Capture

```swift
import GStreamer

let source = try VideoSource.webcam()
    .withResolution(.hd720p)
    .withFramerate(30)
    .withJPEGEncoding(quality: 85)
    .build()

for try await frame in source.frames() {
    // Encoded bytes are available via frame.bytes
}
```

### Audio Capture

```swift
import GStreamer

let mic = try AudioSource.microphone()
    .withSampleRate(48_000)
    .withChannels(2)
    .withOpusEncoding(bitrate: 128_000)
    .build()

for await packet in mic.packets() {
    // Encoded bytes in packet.bytes
}
```

Encoded packet streams are realtime best-effort streams; older packets may be
dropped under slow-consumer backpressure.

### Reliable Live Audio Packets

Status: reliable packet delivery is a non-core v0.1 convenience layer for
encoded audio. It documents explicit delivery policy, but it does not make live
devices indefinitely lossless.

Use `withReliableDelivery(...)` when encoded live audio needs explicit queue
policy, structured discontinuity metadata, and graceful EOS drain. This phase is
encoded audio only; configure Opus or AAC before `build()`.

```swift
import GStreamer

let mic = try AudioSource.microphone()
    .withOpusEncoding(bitrate: 128_000)
    .withReliableDelivery(leaky: .none, maxBuffers: 256, maxTime: .seconds(2))
    .build()

let packets = try mic.reliablePackets()

let reader = Task {
    for try await packet in packets {
        if let discontinuity = packet.priorDiscontinuity {
            print("boundary changed: \(discontinuity.kind)")
        }
        print("packet \(packet.payload.size) bytes")
    }
}

try await Task.sleep(for: .seconds(10))
try await mic.finalize(timeout: .seconds(5))
try await reader.value
```

`QueueLeaky.none` avoids silent GStreamer queue drops while the consumer keeps
up, but a slow consumer can block upstream and expose source xruns. Choose
`.downstream` when lower latency is more important than completeness, or
`.upstream` to keep older queued data and drop new arrivals. `stop()` remains an
immediate shutdown; `finalize(timeout:)` is the reliable EOS-drain path.

### Reliable File Audio Packets

Status: file reliable packet delivery is a non-core v0.1 convenience layer for
finite local file/decode workflows where backpressure is possible.

Use `AudioSource.file(path:)` for finite file/decode workloads where every
packet must be delivered in order. The resulting `AudioFileSource` is
repeatable; each `reliablePackets()` call creates a fresh single-consumer
sequence.

```swift
import GStreamer

let source = try AudioSource.file(path: "/tmp/input.wav")
    .withEncoding(.raw)
    .build()

do {
    for try await packet in source.reliablePackets() {
        print("packet \(packet.size) bytes")
    }
    print("Reached EOS")
} catch is CancellationError {
    print("Cancelled")
} catch {
    print("Pipeline failed: \(error)")
}
```

File reliable delivery is repeatable and backpressureable. Live reliable
delivery is source-owned and single-sequence because it wraps one live appsink.
Start with the DocC article `APIContract` for the consolidated contract, then
see `EncodedPacketDelivery` for packet-specific details.

### Audio Playback

```swift
import GStreamer

let speaker = try AudioSink.speaker()
    .withSampleRate(48_000)
    .withChannels(2)
    .withFormat(.s16le)
    .build()

let buffer: AudioBuffer = /* ... */
try await speaker.play(buffer)
```

### Device Enumeration

```swift
let cameras = try VideoSource.availableWebcams()
let microphones = try AudioSource.availableMicrophones()
let speakers = try AudioSink.availableSpeakers()
```

## Examples

- `Examples/gst-video-source`: ergonomic webcam capture with encoding fallback
- `Examples/gst-audio-source`: ergonomic microphone capture with Opus fallback
- `Examples/gst-audio-sink`: ergonomic speaker playback (sine tone)
- `Examples/`: additional low-level pipelines, appsink/appsrc, and platform demos

### Setting Element Properties

```swift
let pipeline = try Pipeline("videotestsrc name=src ! autovideosink")

if let src = pipeline.element(named: "src") {
    src.set("pattern", 0)        // Int property
    src.set("is-live", true)     // Bool property
    src.set("name", "my-source") // String property
}
```

## Manual Platform Notes

These notes are platform-specific starting points, not v0.1 support guarantees.
The first-class v0.1 setup path is macOS/Homebrew or Ubuntu/Debian with the
required GStreamer development packages available through `pkg-config`.

### Fedora/RHEL Setup

```bash
# Core development libraries
sudo dnf install \
    pkgconf-pkg-config \
    gstreamer1-devel \
    gstreamer1-plugins-base-devel

# Runtime plugins
sudo dnf install \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-ugly-free \
    gstreamer1-libav
```

### Arch Linux Setup

```bash
sudo pacman -S pkgconf gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
```

### Webcam Capture (Linux v4l2src)

Capture frames from a USB webcam on Linux:

```swift
import GStreamer

// Basic webcam capture
let pipeline = try Pipeline("""
    v4l2src device=/dev/video0 ! \
    videoconvert ! \
    video/x-raw,format=BGRA,width=640,height=480 ! \
    appsink name=sink
    """)

let sink = try pipeline.appSink(named: "sink")
try pipeline.play()

for await frame in sink.frames() {
    print("Webcam frame: \(frame.width)x\(frame.height)")

    try frame.withUnsafeBytes { buffer in
        // Process webcam pixels - send to ML model, save to disk, etc.
    }
}
```

High-resolution capture with specific framerate:

```swift
let pipeline = try Pipeline("""
    v4l2src device=/dev/video0 ! \
    video/x-raw,width=1920,height=1080,framerate=30/1 ! \
    videoconvert ! \
    video/x-raw,format=BGRA ! \
    appsink name=sink
    """)
```

### Audio Capture (Linux alsasrc)

Capture audio from ALSA devices:

```swift
import GStreamer

// Capture from default ALSA device
let pipeline = try Pipeline("""
    alsasrc device=default ! \
    audioconvert ! \
    audio/x-raw,format=S16LE,rate=44100,channels=2 ! \
    appsink name=sink
    """)

// Or from a specific hardware device
let pipeline = try Pipeline("""
    alsasrc device=hw:0,0 ! \
    audioconvert ! \
    audio/x-raw,format=S16LE,rate=48000,channels=1 ! \
    appsink name=sink
    """)
```

### PipeWire Audio (Modern Linux)

PipeWire is the modern audio/video server on Linux (default on Fedora, Ubuntu 22.10+, etc.). Install the GStreamer plugin:

```bash
# Ubuntu/Debian
sudo apt install gstreamer1.0-pipewire

# Fedora
sudo dnf install gstreamer1-plugin-pipewire

# Arch
sudo pacman -S gst-plugin-pipewire
```

Capture audio from PipeWire:

```swift
import GStreamer

// Capture from default PipeWire audio source (microphone)
let pipeline = try Pipeline("""
    pipewiresrc ! \
    audioconvert ! \
    audio/x-raw,format=S16LE,rate=16000,channels=1 ! \
    appsink name=sink
    """)

let sink = try pipeline.audioBufferSink(named: "sink")
try pipeline.play()

for await buffer in sink.buffers() {
    print("Audio: \(buffer.sampleCount) samples at \(buffer.sampleRate)Hz")

    buffer.bytes.withUnsafeBytes { bytes in
        let samples = bytes.bindMemory(to: Int16.self)
        // Process audio samples - speech recognition, etc.
    }
}
```

Capture video from PipeWire (screen capture, camera):

```swift
// Screen capture via PipeWire portal
let pipeline = try Pipeline("""
    pipewiresrc ! \
    videoconvert ! \
    video/x-raw,format=BGRA ! \
    appsink name=sink
    """)

let sink = try pipeline.appSink(named: "sink")
try pipeline.play()

for await frame in sink.frames() {
    print("Screen: \(frame.width)x\(frame.height)")
}
```

Play audio to PipeWire:

```swift
// Play audio to default output
let pipeline = try Pipeline("""
    appsrc name=src ! \
    audio/x-raw,format=S16LE,rate=44100,channels=2,layout=interleaved ! \
    audioconvert ! \
    pipewiresink
    """)

let src = try AppSource(pipeline: pipeline, name: "src")
src.setCaps("audio/x-raw,format=S16LE,rate=44100,channels=2,layout=interleaved")
try pipeline.play()

// Push audio samples
try src.push(data: audioSamples, pts: pts, duration: duration)
```

### PulseAudio (Linux)

PulseAudio is widely used on older Linux systems. Install the plugin:

```bash
# Ubuntu/Debian
sudo apt install gstreamer1.0-pulseaudio

# Fedora
sudo dnf install gstreamer1-plugins-good

# Arch
sudo pacman -S gst-plugins-good
```

Capture audio from PulseAudio:

```swift
import GStreamer

// Capture from default PulseAudio source
let pipeline = try Pipeline("""
    pulsesrc ! \
    audioconvert ! \
    audio/x-raw,format=S16LE,rate=16000,channels=1 ! \
    appsink name=sink
    """)

let sink = try pipeline.audioBufferSink(named: "sink")
try pipeline.play()

for await buffer in sink.buffers() {
    buffer.bytes.withUnsafeBytes { bytes in
        let samples = bytes.bindMemory(to: Int16.self)
        // Send to speech recognition, voice assistant, etc.
    }
}
```

Capture from a specific PulseAudio device:

```swift
// List devices with: pactl list sources short
let pipeline = try Pipeline("""
    pulsesrc device=alsa_input.usb-Blue_Microphones-00 ! \
    audioconvert ! \
    audio/x-raw,format=S16LE,rate=48000,channels=1 ! \
    appsink name=sink
    """)
```

Play audio to PulseAudio:

```swift
let pipeline = try Pipeline("""
    appsrc name=src ! \
    audio/x-raw,format=S16LE,rate=44100,channels=2,layout=interleaved ! \
    audioconvert ! \
    pulsesink
    """)
```

### Low-Level Device Enumeration

For direct access to GStreamer devices and properties, use `DeviceMonitor`:

```swift
import GStreamer

let monitor = DeviceMonitor()

// List all cameras
print("Cameras:")
for camera in monitor.videoSources() {
    print("  - \(camera.displayName)")
    if let path = camera.property("device.path") {
        print("    Path: \(path)")
    }
}

// List all microphones
print("Microphones:")
for mic in monitor.audioSources() {
    print("  - \(mic.displayName)")
}

// Create a pipeline element from a device
if let camera = monitor.videoSources().first,
   let source = camera.createElement(name: "cam") {
    // Use source element in your pipeline
}
```

### RTSP Camera Stream

Receive video from IP cameras:

```swift
import GStreamer

let pipeline = try Pipeline("""
    rtspsrc location=rtsp://camera.local/stream latency=100 ! \
    rtph264depay ! h264parse ! \
    avdec_h264 ! \
    videoconvert ! \
    video/x-raw,format=BGRA ! \
    appsink name=sink
    """)

let sink = try pipeline.appSink(named: "sink")
try pipeline.play()

for await frame in sink.frames() {
    // Process RTSP frames
}
```

### Working with Caps

```swift
let caps = try Caps("video/x-raw,format=BGRA,width=1920,height=1080,framerate=30/1")
print(caps.description)
```

## API Reference

### Core: Initialization

```swift
public enum GStreamer {
    static func initialize(_ config: Configuration = .init()) throws
    static var versionString: String { get }
    static var isInitialized: Bool { get }
}
```

### Core: Pipeline, Elements, and Bus Access

```swift
public final class Pipeline: @unchecked Sendable {
    init(_ description: String) throws
    func play() throws
    func pause() throws
    func stop()
    func setState(_ state: State) throws
    func currentState() -> State
    var bus: Bus { get }
    func element(named name: String) -> Element?
    func appSink(named name: String) throws -> AppSink
    func audioBufferSink(named name: String) throws -> AudioBufferSink
    func appSource(named name: String) throws -> AppSource
}
```

### Convenience and Experimental Builders

```swift
public final class VideoSource: @unchecked Sendable {
    static func availableWebcams() throws -> [WebcamInfo]
    static func webcam(deviceIndex: Int = 0) -> VideoSourceBuilder
    static func webcam(name: String) throws -> VideoSourceBuilder
    static func webcam(devicePath: String) throws -> VideoSourceBuilder
    static func testPattern() -> VideoSourceBuilder
    func frames() -> AppSink.Frames
}

public final class AudioSource: @unchecked Sendable {
    static func availableMicrophones() throws -> [AudioDeviceInfo]
    static func microphone(deviceIndex: Int = 0) -> AudioSourceBuilder
    static func microphone(name: String) throws -> AudioSourceBuilder
    static func microphone(devicePath: String) throws -> AudioSourceBuilder
    static func file(path: String) -> AudioFileSourceBuilder
    func buffers() -> AsyncStream<AudioBuffer>
    func packets() -> AsyncStream<Buffer>
    func reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>>
}

public final class AudioSink: @unchecked Sendable {
    static func availableSpeakers() throws -> [AudioDeviceInfo]
    static func speaker(deviceIndex: Int = 0) -> AudioSinkBuilder
    static func speaker(name: String) throws -> AudioSinkBuilder
    static func speaker(devicePath: String) throws -> AudioSinkBuilder
    func play(_ buffer: AudioBuffer) async throws
    func play(_ buffer: Buffer) async throws
}

public struct AudioFileSource: Sendable {
    func reliablePackets() -> ReliablePackets<Buffer>
}
```

### Experimental Typed Pipeline DSL

```swift
@resultBuilder
public struct VideoPipelineBuilder: Sendable { ... }

public struct PartialPipeline<Element: Sendable>: Sendable { ... }

public func runPipeline(
    @VideoPipelineBuilder buildPipeline: @Sendable () -> PartialPipeline<Never>
) async throws

public func withPipeline<Frame: VideoFrameProtocol>(
    @VideoPipelineBuilder buildPipeline: @Sendable () -> PartialPipeline<Frame>,
    withEachFrame: @Sendable (Frame) async throws -> Void
) async throws
```

### Core: Bus and Messages

```swift
public enum BusMessage: Sendable {
    case eos
    case error(message: String, debug: String?)
    case warning(message: String, debug: String?)
    case stateChanged(old: Pipeline.State, new: Pipeline.State)
    case element(name: String, fields: [String: String])
}

public final class Bus: @unchecked Sendable {
    struct Messages: AsyncSequence, Sendable { ... }
    func messageSequence(filter: Filter = .all) -> Messages
    func messages(filter: Filter = [.error, .eos, .stateChanged]) -> AsyncStream<BusMessage>
}
```

### Core: AppSink, AppSource, and Video Frames

```swift
public final class AppSink: @unchecked Sendable {
    init(pipeline: Pipeline, name: String) throws
    func frames() -> AppSink.Frames
}

public struct VideoFrame: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let format: PixelFormat
    public var bytes: RawSpan
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R
}

public enum PixelFormat: Sendable, Equatable {
    case bgra, rgba, nv12, i420, gray8, unknown(String)
}
```

### Core: Audio Buffers

```swift
public final class AudioBufferSink: @unchecked Sendable {
    init(pipeline: Pipeline, name: String) throws
    func buffers() -> AsyncStream<AudioBuffer>
}

public struct AudioBuffer: @unchecked Sendable {
    let sampleRate: Int
    let channels: Int
    let format: AudioFormat
}
```

## License

MIT License. See [LICENSE](LICENSE) for details.
