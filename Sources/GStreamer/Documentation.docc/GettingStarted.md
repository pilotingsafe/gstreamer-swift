# Getting Started with GStreamer

Learn how to set up GStreamer and create your first video pipeline.

## Overview

This guide walks you through installing GStreamer, adding the Swift package to your project, and creating a simple video processing pipeline.

## Installation

### macOS

Install GStreamer using Homebrew:

```bash
brew install pkgconf gstreamer
```

### Linux (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-tools
```

For other platform-specific pipeline examples, see <doc:PlatformGuide>.

## Adding the Package

Add GStreamer to your `Package.swift`:

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

Then add it to your target:

```swift
.target(
    name: "MyApp",
    dependencies: ["GStreamer"]
)
```

## Your First Pipeline

### Initialize GStreamer

Always initialize GStreamer before creating pipelines:

```swift
import GStreamer

@main
struct MyApp {
    static func main() async throws {
        try GStreamer.initialize()
        print("GStreamer version: \(GStreamer.versionString)")

        // Your pipeline code here
    }
}
```

### Create a Test Pipeline

Start with a simple test pattern:

```swift
// Create a pipeline that displays a test pattern
let pipeline = try Pipeline("videotestsrc ! autovideosink")
try pipeline.play()

// Wait for the window to close
for await message in pipeline.bus.messages() {
    if case .eos = message {
        break
    }
}

pipeline.stop()
```

See <doc:APIContract> before composing additional bus consumers, reliable
packet streams, or shutdown flows.

### Process Video Frames

To process video frames in your application, use `appsink`:

```swift
// Create a pipeline with appsink
let pipeline = try Pipeline("""
    videotestsrc num-buffers=100 ! \
    video/x-raw,format=BGRA,width=320,height=240 ! \
    appsink name=sink
    """)

let sink = try pipeline.appSink(named: "sink")
try pipeline.play()

var frameCount = 0
for await frame in sink.frames() {
    frameCount += 1
    print("Frame \(frameCount): \(frame.width)x\(frame.height) \(frame.format)")
}

print("Processed \(frameCount) frames")
pipeline.stop()
```

## Next Steps

- <doc:APIContract>
- <doc:WorkingWithVideoFrames>
- <doc:PlatformGuide>
- ``Pipeline``
