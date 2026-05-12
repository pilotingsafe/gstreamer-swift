# PRD: Reliable Packet Zero-Buffer and Bus EOS Error Handling Fixes

## Introduction/Overview

This PRD covers targeted correctness fixes found during review of reliable packet delivery and bus convenience APIs.

First, `AudioFileSource.reliablePackets()` currently treats a zero-length `GstBuffer` as `GStreamerError.bufferMapFailed`. Zero-length buffers can be legitimate marker or boundary samples in encoded streams, and adjacent paths already skip them. The reliable file path should skip those samples and continue waiting for the next packet.

Second, `Bus.waitForEOS()` currently waits only for EOS. If the pipeline posts ERROR before EOS, the filtered bus consumer can discard the ERROR and keep waiting forever. The API should gain a throwing EOS-or-error helper, while the existing non-throwing helper remains source-compatible but deprecated and no longer hangs on ERROR. The throwing helper must also propagate cancellation instead of reporting cancelled waits as successful EOS completion.

## Status

Last updated: 2026-05-11.

- PRD: implemented.
- Implementation: completed in commit `9790e93` (`Fix reliable packet markers and bus EOS waits`).
- Verification:
  - `swiftly run swift build` passed.
  - `swiftly run swift test --filter ReliablePacketZeroLengthMarkerTests` passed.
  - `swiftly run swift test --filter BusMessageSequenceTests` passed.
  - `swiftly run swift test --filter APISafetyStaticTests` passed.
- Scope: reliable zero-length packet markers, EOS-or-error bus waiting, and cancellation propagation from cancelled EOS waits.
- Related APIs: `AudioFileSource.reliablePackets()`, `Bus.waitForEOS()`, and new `Bus.waitForEOSOrError()`.

## Goals

- Allow reliable file packet iteration to survive legitimate zero-length `GstBuffer` samples.
- Keep zero-length marker samples invisible to public `ReliablePackets<Buffer>` consumers.
- Add a throwing bus helper that returns on EOS and throws on pipeline ERROR.
- Preserve source compatibility for existing `waitForEOS()` call sites.
- Prevent existing `waitForEOS()` callers from hanging forever when ERROR arrives before EOS.
- Add deterministic regression tests for these fixes.

## User Stories

### US-001: Skip Zero-Length Reliable File Buffers Before First Packet

**Description:** As a reliable packet consumer, I want a file source with a zero-length marker before its first real packet to continue reading so that valid encoded output is not misclassified as startup failure.

**Acceptance Criteria:**
- [x] A deterministic reliable file test feeds a zero-length sample followed by a non-empty sample through a custom candidate pipeline.
- [x] Iteration over `AudioFileSource.reliablePackets()` yields the non-empty sample.
- [x] The zero-length sample does not yield a public `Buffer`.
- [x] Iteration does not throw `GStreamerError.bufferMapFailed`.
- [x] The zero-length sample is not recorded as startup failure or candidate exhaustion.
- [x] Focused reliable packet tests pass.

### US-002: Skip Zero-Length Reliable File Buffers After First Packet

**Description:** As a reliable packet consumer, I want a zero-length marker after packet delivery has started to be skipped so that iteration does not terminate with a buffer mapping error.

**Acceptance Criteria:**
- [x] A deterministic reliable file test feeds non-empty, zero-length, then non-empty samples through a custom candidate pipeline.
- [x] Iteration yields exactly the two non-empty samples in order.
- [x] The zero-length sample does not yield a public `Buffer`.
- [x] Iteration reaches clean EOS without throwing.
- [x] Focused reliable packet tests pass.

### US-003: Add Throwing EOS-Or-Error Bus Wait Helper

**Description:** As a bus consumer, I want a helper that waits for normal completion or pipeline failure so that simple playback code does not need to run a separate error monitor.

**Acceptance Criteria:**
- [x] Add `public func waitForEOSOrError() async throws` to `Bus`.
- [x] The helper listens with filter `[.eos, .error]`.
- [x] The helper returns when it receives `.eos`.
- [x] When it receives `.error(message, debug)`, it throws `GStreamerError.busError(message, source: nil, debug: debug)`.
- [x] The thrown error preserves the exact `message` and `debug` from `BusMessage.error`.
- [x] The thrown error always uses `source: nil`, because `BusMessage.error` does not currently expose source.
- [x] The helper throws `CancellationError` when cancelled before receiving EOS or ERROR.
- [x] Focused bus message tests pass.

### US-004: Deprecate Existing Non-Throwing `waitForEOS()`

**Description:** As an existing caller, I want current `waitForEOS()` code to keep compiling, while new code is guided toward the throwing API.

**Acceptance Criteria:**
- [x] Keep `public func waitForEOS() async` source-compatible.
- [x] Mark `waitForEOS()` deprecated with a migration message pointing callers to `waitForEOSOrError()`.
- [x] Implement deprecated `waitForEOS()` by delegating to `waitForEOSOrError()` and swallowing any thrown error.
- [x] `waitForEOS()` returns instead of hanging when an ERROR arrives before EOS.
- [x] Static API safety tests cover the new public method and deprecation marker.
- [x] Existing finite-pipeline `waitForEOS()` tests continue to pass.

## Functional Requirements

- **FR-1:** In the file reliable packet path, a sample with no `GstBuffer` remains an error and must still throw `GStreamerError.bufferMapFailed`.
- **FR-2:** In the file reliable packet path, a sample whose `GstBuffer` has size `0` must be treated as a marker sample and skipped.
- **FR-3:** Skipping a zero-length buffer must not call `swift_gst_buffer_ref` and must not create a public `Buffer`.
- **FR-4:** Skipping a zero-length buffer must return control to the existing wait loop so the next sample, EOS, bus error, or cancellation decides the next iterator result.
- **FR-5:** Skipping a zero-length buffer before first packet must not trigger encoder candidate fallback or startup failure.
- **FR-6:** Skipping a zero-length buffer after first packet must not terminate the `ReliablePackets` sequence or throw to the consumer.
- **FR-7:** `Bus.waitForEOSOrError() async throws` must be public.
- **FR-8:** `waitForEOSOrError()` must consume bus messages with filter `[.eos, .error]`.
- **FR-9:** `waitForEOSOrError()` must return normally on `.eos`.
- **FR-10:** `waitForEOSOrError()` must throw `GStreamerError.busError(message, source: nil, debug: debug)` on `.error(message, debug)`.
- **FR-11:** `waitForEOSOrError()` must throw `CancellationError` if its task is cancelled before EOS or ERROR.
- **FR-12:** `waitForEOS()` must remain public with signature `async`.
- **FR-13:** `waitForEOS()` must be deprecated and must not hang forever on a bus ERROR.
- **FR-14:** Documentation for `waitForEOS()` must direct callers that need error handling to `waitForEOSOrError()`.

## Non-Goals (Out of Scope)

- **NG-1:** No live reliable packet discontinuity propagation is added to file reliable packets.
- **NG-2:** No zero-length `Buffer` is emitted to public consumers.
- **NG-3:** No change to realtime/lossy `packets()` behavior.
- **NG-4:** No change to `Bus.messages(filter:)`, `Bus.messageSequence(filter:)`, `Bus.errors()`, `Bus.warnings()`, or `Bus.stateChanges()` signatures.
- **NG-5:** No new `BusMessage.error` source field.
- **NG-6:** No real Opus/AAC environment-dependent regression test is required.
- **NG-7:** No broad refactor of bus ownership, fan-out, or polling internals.

## Technical Considerations

- The zero-buffer implementation is in `AudioFileSource`'s reliable `pullPacket(from:)` path: the zero-size `bufferMapFailed` branch is replaced with a skip path.
- Keep the nil-`GstBuffer` branch unchanged as `bufferMapFailed`; only size-zero buffers are valid markers for this PRD.
- Deterministic reliable packet tests can use a custom candidate pipeline with `appsrc name=zero_src ... ! appsink name=reliable_sink ...` and drive empty/non-empty payloads through `AppSource` from the candidate-start hook.
- For the pre-first-packet test, feed empty then non-empty then EOS.
- For the post-first-packet test, feed non-empty then empty then non-empty then EOS.
- The new bus helper should mirror the existing `runPipeline` conversion from `BusMessage.error` to `GStreamerError.busError` with `source: nil`.
- The new bus helper should throw `CancellationError` after the pull sequence ends, because `Bus.Messages.AsyncIterator.next()` returns `nil` on cancellation and EOS is delivered as a value.
- Deprecated `waitForEOS()` should intentionally swallow the thrown error from `waitForEOSOrError()`; callers that need the error payload must migrate to the new API.

## Success Metrics

- Reliable file packet tests prove zero-length buffers before and after first packet are skipped without throwing.
- Bus tests prove `waitForEOSOrError()` returns on EOS and throws exact `GStreamerError.busError(message, source: nil, debug: debug)` on ERROR.
- Bus tests prove `waitForEOSOrError()` throws `CancellationError` when cancelled before EOS or ERROR.
- Bus tests prove deprecated `waitForEOS()` returns on ERROR instead of timing out.
- Static API checks prove `waitForEOSOrError()` exists and `waitForEOS()` is deprecated but source-compatible.
- Focused `swiftly run swift test` runs for reliable packet and bus behavior pass.

## Open Questions

- None. The implementation choices are fixed for this PRD.
