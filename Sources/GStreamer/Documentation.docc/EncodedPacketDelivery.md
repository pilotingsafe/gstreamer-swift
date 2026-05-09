# Encoded Packet Delivery

Choose between realtime best-effort streams and reliable archival streams.

## Overview

`AudioSource.packets()` is a realtime stream. It uses bounded newest-buffer
backpressure and can drop older packets when the consumer is slower than the
capture source. This is the right tradeoff for live microphone capture.

`AudioFileSource.reliablePackets()` is a file/decode stream. It is
consumer-driven, throws pipeline failures, and does not drain packets into an
unbounded Swift queue. Each call to ``AudioFileSource/reliablePackets()`` creates
a fresh ``ReliablePackets`` value, and each ``ReliablePackets`` value supports
one active consumer.

```text
Need packets from a live capture device?
  -> Use AudioSource.packets(); configure upstream realtime policy explicitly.

Need every packet from a local finite file?
  -> Use AudioSource.file(path:).build().reliablePackets().

Need video reliable packets or live-source reliable semantics?
  -> Out of scope for this phase.
```

## File Audio

Build a file source, then iterate until EOS:

```swift
let source = try AudioSource.file(path: "/tmp/input.wav")
    .withEncoding(.raw)
    .build()

for try await packet in source.reliablePackets() {
    print(packet.size)
}
```

Clean EOS after at least one delivered packet ends iteration with `nil`. If all
candidate file/decode pipelines reach EOS before producing any decodable audio
packet, iteration throws `GStreamerError.busError("No decodable audio packets",
source: "ReliablePackets", debug: nil)`.

Startup timeout before the first packet throws
`GStreamerError.busError("Reliable packet startup timed out", source:
"ReliablePackets", debug: "No decodable audio packet arrived before startup
timeout")` after candidate fallback is exhausted.

## Cancellation

Cancelling a task suspended in `next()` resumes it with `CancellationError` and
detaches the appsink callback before the pipeline is stopped. Breaking out of a
`for try await` loop cleans up the pipeline without sending EOS.

## Single Consumer

`AudioFileSource` is repeatable:

```swift
let first = source.reliablePackets()
let second = source.reliablePackets()
```

Both sequences are independent. A single ``ReliablePackets`` value is not
multi-consumer; trying to iterate it from more than one task throws
`GStreamerError.invalidArgument`.

## Formats

Raw and Opus reliable streams are covered by the Phase 1 behavioral tests. AAC
is part of the API and pipeline generation, but behavioral AAC coverage depends
on an AAC encoder being available in the local GStreamer installation.

`Buffer` exposes packet bytes, size, and timestamps. It does not expose per-packet
sample caps; configure raw output caps on ``AudioFileSourceBuilder`` with
`withFormat(_:)`, `withSampleRate(_:)`, and `withChannels(_:)`.
