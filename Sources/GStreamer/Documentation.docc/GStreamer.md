# ``GStreamer``

A Swift package that wraps GStreamer with low-level Swift APIs and selected
concurrency-friendly helpers.

## Overview

GStreamer for Swift provides direct wrappers around pipelines, elements, bus
messages, app sinks, app sources, and buffers. Convenience builders for common
audio and video flows are layered on top of those lower-level APIs.

```swift
import GStreamer

try GStreamer.initialize()

// Create a pipeline that captures from webcam
let pipeline = try Pipeline("""
    v4l2src device=/dev/video0 ! \
    videoconvert ! \
    video/x-raw,format=BGRA,width=640,height=480 ! \
    appsink name=sink
    """)

let sink = try pipeline.appSink(named: "sink")
try pipeline.play()

// Process frames with async/await
for await frame in sink.frames() {
    try frame.withUnsafeBytes { buffer in
        // Process raw BGRA pixels
    }
}
```

## Featured

Start with <doc:GettingStarted> and <doc:APIContract>, then explore typed
pipelines, frame access, video capture, audio capture, audio devices, and
platform-specific pipelines from the topic groups below.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:APIContract>
- ``GStreamer``
- ``Pipeline``

### Video Processing

- <doc:TypedPipelines>
- <doc:WorkingWithVideoFrames>
- <doc:VideoSourceGuide>
- ``VideoSource``
- ``AppSink``
- ``VideoFrame``
- ``PixelFormat``

### Audio Processing

- <doc:AudioCapture>
- <doc:EncodedPacketDelivery>
- <doc:AudioDevices>
- ``AudioSource``
- ``AudioFileSource``
- ``ReliablePackets``
- ``ReliablePacket``
- ``Discontinuity``
- ``AudioSink``
- ``AudioBufferSink``
- ``AudioBuffer``
- ``AudioFormat``

### Device Discovery

- ``DeviceMonitor``
- ``Device``

### Pipeline Components

- ``Element``
- ``Caps``
- ``Bus``
- ``BusMessage``
- ``Tee``
- ``Pad``

### Data Input

- ``AppSource``

### Error Handling

- ``GStreamerError``

### Platform Guides

- <doc:PlatformGuide>
