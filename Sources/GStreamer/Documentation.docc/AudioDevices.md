# Audio Sources and Outputs

Capture from microphones and play to speakers with convenience builders.

## Overview

Status: ``AudioSource``, ``AudioSourceBuilder``, ``AudioSink``, and
``AudioSinkBuilder`` are non-core v0.1 convenience APIs. They compose common
capture and playback pipelines over the low-level wrappers; use direct
``Pipeline``, ``AudioBufferSink``, and ``AppSource`` APIs when you need exact
GStreamer element control.

``AudioSource`` and ``AudioSink`` build audio pipelines using the devices and
GStreamer backends available on the current platform. They provide device
enumeration, format configuration, and optional encoding for capture.

## Enumerating Devices

```swift
let microphones = try AudioSource.availableMicrophones()
let speakers = try AudioSink.availableSpeakers()

for mic in microphones {
    print("Mic: \(mic.name) (\(mic.uniqueID))")
}

for speaker in speakers {
    print("Speaker: \(speaker.name) (\(speaker.uniqueID))")
}
```

## Capture Raw PCM

```swift
let mic = try AudioSource.microphone(deviceIndex: 0)
    .withSampleRate(48_000)
    .withChannels(2)
    .withFormat(.s16le)
    .build()

for await buffer in mic.buffers() {
    print("\(buffer.sampleRate)Hz \(buffer.channels)ch \(buffer.format)")
}
```

## Capture Encoded Audio

Encoded packet streams are realtime best-effort streams. They keep a bounded
queue of recent packets and may drop older packets under slow-consumer
backpressure.

```swift
let mic = try AudioSource.microphone()
    .withSampleRate(48_000)
    .withChannels(2)
    .withOpusEncoding(bitrate: 128_000)
    .build()

for await packet in mic.packets() {
    // Encoded bytes in packet.bytes
}
```

## Play Audio

```swift
let speaker = try AudioSink.speaker(deviceIndex: 0)
    .withSampleRate(48_000)
    .withChannels(2)
    .withFormat(.s16le)
    .build()

// Play a buffer (e.g., from a microphone or file pipeline)
let buffer: AudioBuffer = /* ... */
try await speaker.play(buffer)
```

## Notes

``AudioBufferSink`` remains the lower-level appsink wrapper for raw audio
capture. Use ``AudioSource`` when a convenience builder fits the application.
