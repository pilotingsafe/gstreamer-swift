# API Contract

Use this page as the starting point for user-visible lifecycle, bus, and packet
delivery rules.

## Overview

GStreamer for Swift is a low-level wrapper around GStreamer primitives with
selected convenience helpers layered on top. The lower-level APIs preserve
GStreamer's ownership and consumption model: some streams are best-effort,
some are reliable within an explicit scope, and several surfaces are
single-consumer by design.

Detailed guides and symbol documentation describe each API in depth. This page
summarizes the shared contracts that apply across those APIs.

## Bus Consumers

Treat each ``Bus`` as having one active drainer. `messageSequence(filter:)`,
`messages(filter:)`, `errors()`, `warnings()`, `stateChanges()`,
`waitForEOSOrError()`, and convenience APIs that wait on the bus all compete
for the same destructive GStreamer bus queue.

The package does not provide bus fan-out, replay, an observer registry, or bus
ownership transfer. If more than one bus consumer is active, each consumer can
hide messages from the others.

`messageSequence(filter:)` is the pull-based bus API. It returns EOS and ERROR
as values, so the caller decides when to break from the loop. It uses a bounded
parsed-message buffer with best-effort overflow handling that prefers keeping
ERROR and EOS observable over older noncritical messages.

`messages(filter:)` is the compatibility `AsyncStream` API. It finishes after
delivering EOS. The helper streams built on top of it share the same destructive
bus-draining behavior.

## Packet Delivery

`AudioSource.packets()` is a realtime best-effort stream. It uses bounded
newest-buffer backpressure and may drop older packets when the consumer is
slower than the capture source.

`AudioSource.reliablePackets()` is live encoded-audio delivery. It requires
``AudioSourceBuilder/withReliableDelivery(leaky:maxBuffers:maxBytes:maxTime:)``
before `build()`, inserts an explicit GStreamer queue, and reports delivery
boundaries with ``Discontinuity`` metadata.

`AudioFileSource.reliablePackets()` is finite file/decode delivery. It is
consumer-driven, throws pipeline failures, and reaches EOS through iteration.

## Live Reliability Limits

Swift APIs cannot make live devices indefinitely lossless. The live source,
device driver, operating system, and GStreamer pipeline can still impose
backpressure or drop data.

`QueueLeaky.none` avoids configured GStreamer queue drops while the consumer
keeps up, but sustained slowness can block upstream and expose source xruns or
device-level loss. `QueueLeaky.upstream` drops new incoming buffers when the
queue is full. `QueueLeaky.downstream` drops older queued buffers and keeps
newer data to reduce latency.

Raw reliable live buffers, video reliable packets, branch or fan-out delivery,
and recording convenience APIs are outside this phase unless documented by a
future API.

## Shutdown

`stop()` is immediate. It stops the pipeline and does not guarantee encoder
tail packet delivery.

`finalize(timeout:)` is the live reliable EOS-drain path. It sends EOS, waits
for Bus EOS or ERROR, waits for the iterator to drain or cancel, then stops the
pipeline.

Finite file reliable streams do not require `finalize(timeout:)`; they finish
by iterating until EOS or by throwing a pipeline failure.

## Single Consumers

Each ``ReliablePackets`` value supports one active consumer. A single
``ReliablePackets`` value is not a multicast sequence.

``AudioFileSource`` can create fresh repeatable reliable sequences by calling
`reliablePackets()` again. Live reliable ``AudioSource`` streams should be
treated as one active source-owned sequence. Bus sequences should be treated as
single-drainer surfaces.

Build a dispatcher above these low-level APIs when an application needs fan-out
or multiple observers.

## Where To Read More

- <doc:EncodedPacketDelivery>
- ``Bus``
- ``AudioSource``
- ``AudioFileSource``
- ``ReliablePackets``
