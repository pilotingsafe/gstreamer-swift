# ``GStreamer``

A Swift package that wraps GStreamer with low-level Swift APIs and selected
convenience layers.

## Overview

GStreamer for Swift v0.1 is positioned as a low-level, thin, composable Swift
wrapper around GStreamer. The core public surface provides direct wrappers around
pipelines, elements, bus messages, app sinks, app sources, and buffers while
preserving GStreamer's ownership, bus-consumption, and backpressure model.

Higher-level source/sink builders, the typed pipeline DSL, and reliable packet
delivery are convenience or experimental layers built on top of the core
wrappers. They are useful when their fixed composition choices match your
application, but direct `Pipeline`, `Element`, `AppSink`, `AppSource`, and
`Bus` usage remains the v0.1 foundation.

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

Start with <doc:GettingStarted> and <doc:APIContract> for the v0.1 core
contract, then explore frame access and platform-specific pipelines. Use the
convenience and experimental guides when you want builder-driven sources,
sinks, typed video composition, or reliable encoded packet delivery.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:APIContract>
- ``GStreamer``
- ``Pipeline``

### Core Wrappers

- ``Element``
- ``Caps``
- ``Bus``
- ``BusMessage``
- ``AppSink``
- ``AppSource``
- ``AudioBufferSink``
- ``Buffer``
- ``VideoFrame``
- ``AudioBuffer``
- ``Tee``
- ``Pad``

### Core Video and Audio Guides

- <doc:WorkingWithVideoFrames>
- ``PixelFormat``
- <doc:AudioCapture>
- ``AudioFormat``

### Device Discovery

- ``DeviceMonitor``
- ``Device``

### Convenience and Experimental APIs

- <doc:TypedPipelines>
- <doc:VideoSourceGuide>
- <doc:EncodedPacketDelivery>
- <doc:AudioDevices>
- ``VideoSource``
- ``AudioSource``
- ``AudioFileSource``
- ``ReliablePackets``
- ``ReliablePacket``
- ``Discontinuity``
- ``AudioSink``

### Error Handling

- ``GStreamerError``

### Platform Guides

- <doc:PlatformGuide>
