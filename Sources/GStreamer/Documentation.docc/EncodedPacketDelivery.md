# Encoded Packet Delivery

Choose between realtime best-effort streams and reliable archival streams.

## Overview

Status: reliable packet delivery is a non-core v0.1 convenience layer for
encoded audio and finite file/decode workflows. It defines explicit delivery
contracts above the low-level wrappers, but it does not replace direct
``Pipeline``, ``AppSink``, ``AppSource``, or ``Bus`` usage for custom graphs.

For the cross-cutting lifecycle, bus-draining, packet-delivery, and
single-consumer rules, start with <doc:APIContract>.

`AudioSource.packets()` is a realtime stream. It uses bounded newest-buffer
backpressure and can drop older packets when the consumer is slower than the
capture source. This is the right tradeoff for live microphone capture.

`AudioSource.reliablePackets()` is an encoded live audio stream. It requires
``AudioSourceBuilder/withReliableDelivery(leaky:maxBuffers:maxBytes:maxTime:)``
before `build()`, inserts a bounded GStreamer queue before the encoder, and
returns ``ReliablePackets`` of ``ReliablePacket`` values with structured
``Discontinuity`` metadata.

`AudioFileSource.reliablePackets()` is a file/decode stream. It is
consumer-driven, throws pipeline failures, and does not drain packets into an
unbounded Swift queue. Each call to ``AudioFileSource/reliablePackets()`` creates
a fresh ``ReliablePackets`` value, and each ``ReliablePackets`` value supports
one active consumer.

```text
Need packets from a live capture device?
  -> Use AudioSource.packets() for realtime monitoring.

Need encoded live audio with explicit queue policy and EOS drain?
  -> Use AudioSource.microphone()
       .withOpusEncoding(...)
       .withReliableDelivery(...)
       .build()
       .reliablePackets().

Need every packet from a local finite file?
  -> Use AudioSource.file(path:).build().reliablePackets().

Need raw reliable live buffers, video reliable packets, fan-out, or recording helpers?
  -> Out of scope for this phase.
```

## Live Audio

Reliable live delivery is encoded-audio-only in this phase. Configure Opus or
AAC, choose an explicit queue policy, then iterate one source-owned sequence:

```swift
let source = try AudioSource.microphone()
    .withOpusEncoding(bitrate: 128_000)
    .withReliableDelivery(leaky: .none, maxBuffers: 256, maxTime: .seconds(2))
    .build()

let packets = try source.reliablePackets()

let reader = Task {
    for try await packet in packets {
        if let discontinuity = packet.priorDiscontinuity {
            print(discontinuity.kind)
        }
        print(packet.payload.size)
    }
}

try await Task.sleep(for: .seconds(10))
try await source.finalize(timeout: .seconds(5))
try await reader.value
```

`QueueLeaky.none` blocks upstream when the configured queue is full, favoring no
silent queue drops while the consumer keeps up. Sustained slowness can still
surface source xruns or device-level loss outside the GStreamer queue.
`QueueLeaky.upstream` drops new incoming buffers when full and keeps older
queued data. `QueueLeaky.downstream` drops older queued buffers and keeps newer
data to reduce latency.

Use ``AudioSource/finalize(timeout:)`` for reliable shutdown. It sends EOS,
waits for Bus EOS or ERROR, waits for the iterator to drain or cancel, then
stops the pipeline. ``AudioSource/stop()`` remains immediate and does not
guarantee encoder tail packet delivery.

``Discontinuity`` reports one boundary signal per packet in this order:
format change, DISCONT flag, GAP flag, inferred dropped interval. Its
`duration` is the gap only, and `droppedCount` is reserved for future inference
and is always `nil` in this version.

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

Raw reliable live buffers, VideoSource reliable delivery, branch/fan-out queue
policies, appsink buffer-list handling, and recording convenience APIs are
future work.
