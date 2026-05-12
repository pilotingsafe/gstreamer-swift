# GStreamer

[![CI](https://github.com/wendylabsinc/gstreamer/actions/workflows/ci.yml/badge.svg)](https://github.com/wendylabsinc/gstreamer/actions/workflows/ci.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20Linux-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A modern Swift 6.2 wrapper for GStreamer, designed for robotics and computer vision applications.

## Features

- Swift Concurrency support with `AsyncStream` for bus messages and video frames
- Safe buffer access via `RawSpan` - memory views cannot escape their scope
- Clean, ergonomic API with minimal boilerplate
- Full `Sendable` conformance for safe concurrent access
- Cross-platform: macOS, iOS, tvOS, watchOS, visionOS, and Linux

## Requirements

- Swift 6.2+
- macOS 26.0+ (typed pipelines use value generics, which are only available on macOS 26)
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

**Windows:**

Option 1 - MSYS2 (recommended for Swift):
```powershell
# In MSYS2 UCRT64 terminal
pacman -S mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-gstreamer mingw-w64-ucrt-x86_64-gst-plugins-base mingw-w64-ucrt-x86_64-gst-plugins-good
```

Option 2 - Official Installer:
1. Download from https://gstreamer.freedesktop.org/download/
2. Install both **runtime** and **development** installers; SwiftPM needs the development headers, libraries, and `.pc` files
3. Add to PATH: `C:\gstreamer\1.0\msvc_x86_64\bin`
4. Set `PKG_CONFIG_PATH=C:\gstreamer\1.0\msvc_x86_64\lib\pkgconfig`

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

**Fedora/RHEL:**
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

**Arch Linux:**
```bash
sudo pacman -S pkgconf gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
```

**NVIDIA Jetson (JetPack):**

GStreamer runtime and hardware-accelerated plugins come pre-installed with JetPack, including support for NVENC/NVDEC and the Jetson multimedia API. You only need to install the development headers:
```bash
sudo apt install pkg-config libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Jetson-specific plugins like `nvvidconv`, `nvv4l2decoder`, and `nvarguscamerasrc` are already available.

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
    .package(url: "https://github.com/wendylabsinc/gstreamer.git", from: "0.0.4")
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

### High-Level Video Capture

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

### High-Level Audio Capture

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
See the DocC article `EncodedPacketDelivery` for the full boundary.

### High-Level Audio Playback

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

### Type-Safe Pipelines

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

The sections below use raw pipeline strings for advanced or platform-specific cases.

### Basic Pipeline

```swift
import GStreamer

// Create and run a pipeline (GStreamer auto-initializes)
let pipeline = try Pipeline("videotestsrc num-buffers=100 ! autovideosink")
try pipeline.play()

// Listen for bus messages
messageLoop: for await message in pipeline.bus.messageSequence(filter: [.eos, .error]) {
    switch message {
    case .eos:
        print("End of stream")
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
buffer matching `BusMessage` values before the consumer awaits `next()`. EOS and
ERROR are delivered as values so the caller decides when to break. Use it when
one task owns bus draining and you want to avoid blocking Swift concurrency
threads.

`messages(filter:)` remains the stream-based compatibility API. It uses a
detached producer task and an `AsyncStream`, finishes after delivering EOS, and
continues to back the `errors()`, `warnings()`, and `stateChanges()`
convenience streams. The EOS waiting helpers use `messageSequence(filter:)` and
inherit its single-owner bus-draining behavior. Do not run multiple bus
consumers unless you intend them to compete for the same destructive GStreamer
bus queue.

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

// Process frames using AsyncStream
for await frame in sink.frames() {
    print("Frame: \(frame.width)x\(frame.height) \(frame.format.formatString)")

    // Safe pointer access scoped to this closure
    try frame.withUnsafeBytes { buffer in
        // Process pixel data...
        let firstPixel = Array(buffer.prefix(4)) // BGRA
        print("First pixel: \(firstPixel)")
    }
}

pipeline.stop()
```

### Setting Element Properties

```swift
let pipeline = try Pipeline("videotestsrc name=src ! autovideosink")

if let src = pipeline.element(named: "src") {
    src.set("pattern", 0)        // Int property
    src.set("is-live", true)     // Bool property
    src.set("name", "my-source") // String property
}
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

### NVIDIA Jetson Camera

Use hardware-accelerated capture on NVIDIA Jetson:

```swift
import GStreamer

// CSI camera with nvarguscamerasrc (IMX219, IMX477, etc.)
let pipeline = try Pipeline("""
    nvarguscamerasrc sensor-id=0 ! \
    video/x-raw(memory:NVMM),width=1920,height=1080,framerate=30/1 ! \
    nvvidconv ! \
    video/x-raw,format=BGRA ! \
    appsink name=sink
    """)

let sink = try pipeline.appSink(named: "sink")
try pipeline.play()

for await frame in sink.frames() {
    // Process hardware-accelerated frames
    try frame.withUnsafeBytes { buffer in
        // Run TensorRT inference, etc.
    }
}
```

USB camera on Jetson with hardware conversion:

```swift
let pipeline = try Pipeline("""
    v4l2src device=/dev/video0 ! \
    video/x-raw,width=1280,height=720 ! \
    nvvidconv ! \
    video/x-raw,format=BGRA ! \
    appsink name=sink
    """)
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

### GStreamer

```swift
public enum GStreamer {
    static func initialize(_ config: Configuration = .init()) throws
    static var versionString: String { get }
    static var isInitialized: Bool { get }
}
```

### Pipeline

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

### High-Level APIs

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
    func buffers() -> AsyncStream<AudioBuffer>
    func packets() -> AsyncStream<Buffer>
}

public final class AudioSink: @unchecked Sendable {
    static func availableSpeakers() throws -> [AudioDeviceInfo]
    static func speaker(deviceIndex: Int = 0) -> AudioSinkBuilder
    static func speaker(name: String) throws -> AudioSinkBuilder
    static func speaker(devicePath: String) throws -> AudioSinkBuilder
    func play(_ buffer: AudioBuffer) async throws
    func play(_ buffer: Buffer) async throws
}
```

### Bus & Messages

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

### AppSink & VideoFrame

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

### AudioBufferSink & AudioBuffer

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
