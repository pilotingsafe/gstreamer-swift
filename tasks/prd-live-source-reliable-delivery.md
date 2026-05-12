# PRD: Live Source Reliable Delivery (RFC-002)

## Introduction/Overview

This PRD covers the RFC-002 follow-up for reliable packet delivery from live audio sources. Phase 1 already introduced `ReliablePackets<Element>` for finite file/decode sources. This work extends the reliable delivery model to encoded live `AudioSource` pipelines while keeping the existing realtime `packets()` and raw `buffers()` APIs unchanged.

Live capture cannot promise unlimited no-drop delivery under arbitrary consumer slowness. This PRD therefore requires explicit builder opt-in, direct use of GStreamer's `QueueLeaky` vocabulary, bounded queue configuration, observable discontinuities, and deterministic EOS finalization.

The first implementation phase is encoded audio only (`Opus` and `AAC`). Raw reliable live buffers, VideoSource reliable delivery, tee/fan-out, muxing, and recording convenience APIs are out of scope.

## Status

Last updated: 2026-05-11.

- Drafting: complete.
- RFC update: complete.
- Implementation: complete.
- Functional requirements: all achieved (FR-1 through FR-15).
- Review: ready for maintainer review.
- Verification completed on 2026-05-11:
  - `swift build`
  - `swift test --filter Reliable`
  - `swift test --filter Audio`
  - `swift test --filter APISafetyStaticTests`
  - `swift test`
  - `swift package generate-documentation --target GStreamer`
- Verification notes:
  - During status verification, one `Audio` filter run timed out in `appsinkEOSStateCompletesWhenEOSCallbacksAreSuppressed`; the same case passed in the full suite and a later `swift test --filter Audio` rerun.
  - During status verification, one full-suite run failed in `QueueLeakyBehaviorTests` downstream-leaky behavior; `swift test --filter QueueLeakyBehaviorTests` passed immediately after and the full suite passed on rerun.
  - These are recorded as flake watch items, not open FR gaps.

## Goals

- Update RFC-002 so the accepted decision is GStreamer-aligned and decision-complete.
- Add explicit reliable live delivery opt-in to `AudioSourceBuilder` using `QueueLeaky` and queue bounds.
- Expose encoded live reliable packets through the existing `ReliablePackets` primitive without adding Swift-side unbounded queues.
- Surface discontinuities with structured metadata instead of a simple gap count.
- Provide deterministic live finalization through EOS send, Bus EOS/ERROR wait, and timeout handling.
- Keep realtime `AudioSource.packets()`, raw `AudioSource.buffers()`, `AudioFileSource.reliablePackets()`, and all VideoSource public APIs source-compatible.

## User Stories

### US-001: Revise RFC-002 to the accepted decision

**Description:** As a maintainer, I need RFC-002 to match the accepted live reliable delivery decision so implementation work does not follow stale API sketches.

**Acceptance Criteria:**
- [x] `docs/RFCs/RFC-002-live-source-reliable-delivery.md` no longer recommends or sketches `LiveSourceDeliveryPolicy`.
- [x] RFC-002 recommends direct `QueueLeaky` plus `maxBuffers`, `maxBytes`, and `maxTime` queue bounds.
- [x] RFC-002 replaces `gapsSinceLast: Int` with `ReliablePacket` plus `Discontinuity`.
- [x] RFC-002 AppSink configuration states reliable live appsink is fixed to `max-buffers=1`, not derived from queue bounds.
- [x] RFC-002 API sketch does not add public `VideoSourceBuilder.withReliableDelivery(...)` or `VideoSource.reliablePackets()` in v1.
- [x] RFC-002 tests no longer assert `gapsSinceLast`; they assert `priorDiscontinuity == nil` or specific `Discontinuity.Kind` values.
- [x] RFC-002 accepted scope is encoded `AudioSource` v1, with raw reliable buffers and VideoSource reliable delivery deferred.
- [x] RFC-002 resolves trap-vs-throw in favor of typed thrown errors.
- [x] RFC-002 documents live finalization as `sendEOS()`, wait for Bus EOS/ERROR with timeout, then stop.
- [x] RFC-002 explicitly states public unbounded reliable live configuration is not supported.
- [x] Markdown review confirms no `LiveSourceDeliveryPolicy` references remain except in removed-history discussion if intentionally retained.

### US-002: Add reliable delivery configuration to AudioSourceBuilder

**Description:** As a library user, I want to opt into live reliable delivery at build time so I explicitly choose the queue/backpressure trade-off before capture starts.

**Acceptance Criteria:**
- [x] Add `public func withReliableDelivery(leaky:maxBuffers:maxBytes:maxTime:) -> AudioSourceBuilder` with this signature:

```swift
public func withReliableDelivery(
  leaky: QueueLeaky = .none,
  maxBuffers: UInt? = 256,
  maxBytes: UInt? = nil,
  maxTime: Duration? = .seconds(2)
) -> AudioSourceBuilder
```

- [x] The builder stores reliable delivery configuration immutably and returns a modified copy.
- [x] `build()` rejects reliable delivery with `.raw` encoding by throwing `AudioSource.AudioSourceError.invalidConfiguration("Reliable live packet delivery requires encoded audio output; configure Opus or AAC encoding before build")`.
- [x] `build()` rejects `maxTime < .zero` by throwing `AudioSource.AudioSourceError.invalidConfiguration("Reliable delivery maxTime must be non-negative")`.
- [x] `build()` rejects effectively unbounded public reliable config by throwing `AudioSource.AudioSourceError.invalidConfiguration("Reliable delivery requires at least one finite non-zero queue bound")`.
- [x] Effectively unbounded means `maxBuffers` is `nil` or `0`, `maxBytes` is `nil` or `0`, and `maxTime` is `nil` or `.zero`.
- [x] Swift build passes.

### US-003: Build the reliable live audio pipeline

**Description:** As an implementer, I need the live reliable pipeline to enforce the selected GStreamer queue policy without the appsink absorbing unbounded backlog.

**Acceptance Criteria:**
- [x] When reliable delivery is not configured, current realtime pipeline generation remains unchanged, including `appsink ... drop=true max-buffers=1`.
- [x] When reliable delivery is configured, the pipeline inserts a named `queue` after `audioconvert ! audioresample` and caps normalization, and before the encoder.
- [x] Queue configuration serializes as `leaky=<QueueLeaky.rawValue> max-size-buffers=<maxBuffers or 0> max-size-bytes=<maxBytes or 0> max-size-time=<maxTime nanoseconds or 0>`.
- [x] `nil` and zero bounds serialize to `0`, matching GStreamer's disabled-limit convention.
- [x] Reliable appsink configuration is exactly `drop=false sync=false emit-signals=true enable-last-sample=false wait-on-eos=true max-buffers=1`.
- [x] Reliable appsink does not set `max-bytes`, `max-time`, or `buffer-list` in this phase.
- [x] Pipeline string tests verify queue bounds and appsink settings for Opus and AAC reliable configurations.
- [x] Swift build passes.

### US-004: Add ReliablePacket and Discontinuity public types

**Description:** As a recording or archival caller, I want each live reliable packet to include enough timing and discontinuity metadata to detect and react to gaps.

**Acceptance Criteria:**
- [x] Add public `ReliablePacket<Payload: Sendable>: Sendable` with `payload`, `pts`, `duration`, and `priorDiscontinuity`.
- [x] `pts` and `duration` are `UInt64?` nanoseconds, matching `Buffer.pts` and `Buffer.duration`; do not introduce a public `ClockTime` type in this PRD.
- [x] Add public `Discontinuity: Sendable` with `kind`, `priorPTS`, `priorDuration`, `nextPTS`, `duration`, and `droppedCount`.
- [x] `priorPTS`, `priorDuration`, `nextPTS`, and `duration` are `UInt64?` nanoseconds.
- [x] `Discontinuity.duration` represents gap duration only, not `prior packet + gap` duration.
- [x] `droppedCount` is `Int?`, reserved for future inference, and v1 always returns `nil`.
- [x] `Discontinuity.Kind` cases are exactly `.formatChange`, `.discont`, `.gap`, and `.dropped`.
- [x] Public DocC explains every case and states that only one `priorDiscontinuity` is surfaced per packet in v1.
- [x] Swift build passes.

### US-005: Add buffer flag support for discontinuity detection

**Description:** As an implementer, I need access to GStreamer buffer flags so live reliable packets can reflect GAP and DISCONT signals without guessing.

**Acceptance Criteria:**
- [x] Add internal CGStreamerShim helpers for `gst_buffer_get_flags`.
- [x] Add Swift-side internal helpers to check `GST_BUFFER_FLAG_GAP` and `GST_BUFFER_FLAG_DISCONT`.
- [x] Existing `Buffer` PTS and duration APIs remain source-compatible.
- [x] Focused tests cover flag extraction for GAP and DISCONT where buffers can be constructed with flags.
- [x] Swift build passes.

### US-006: Implement AudioSource.reliablePackets()

**Description:** As a library user, I want an encoded live reliable packet sequence that pulls only when the consumer awaits and surfaces pipeline failures by throwing.

**Acceptance Criteria:**
- [x] Add `public func reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>>` on `AudioSource`.
- [x] If reliable delivery was not configured before build, calling `reliablePackets()` throws `GStreamerError.invalidArgument(parameter: "AudioSource.reliablePackets", reason: "Reliable delivery is not configured; call withReliableDelivery(...) before build().")`.
- [x] The reliable live bridge reuses the Phase 1 `new-sample` signal, continuation, cancellation, and bus error observation pattern.
- [x] The bridge uses `swift_gst_app_sink_try_pull_sample(..., 0)` when woken and never calls blocking `swift_gst_app_sink_pull_sample` from async context.
- [x] `ReliablePackets` remains single-consumer; concurrent `next()` calls are rejected consistently with Phase 1.
- [x] Clean EOS ends iteration with `nil`; Bus errors throw `GStreamerError`.
- [x] Cancellation detaches signal handlers and releases pending continuations synchronously.
- [x] Swift build passes.

### US-007: Detect and surface discontinuities

**Description:** As an archival caller, I need live reliable packets to report whether the previous packet boundary was continuous, a GStreamer gap, a discontinuity, a caps change, or an inferred drop.

**Acceptance Criteria:**
- [x] `.gap` is produced when the current buffer has `GST_BUFFER_FLAG_GAP`.
- [x] `.discont` is produced when the current buffer has `GST_BUFFER_FLAG_DISCONT`.
- [x] `.formatChange` is produced when current sample caps and previous sample caps are not equal according to `gst_caps_is_equal`; string comparison is not used because it can produce false positives from field ordering.
- [x] `.dropped` is produced when `priorPTS + priorDuration < currentPTS` and no higher-precedence discontinuity applies.
- [x] Precedence for multiple signals on one packet is exactly `.formatChange`, then `.discont`, then `.gap`, then `.dropped`.
- [x] `Discontinuity.duration` is derived from `nextPTS - (priorPTS + priorDuration)` only when `priorPTS`, `priorDuration`, and `nextPTS` are all available and `nextPTS >= priorPTS + priorDuration`; otherwise it is `nil`.
- [x] `droppedCount` is always `nil` in v1 and DocC marks it reserved for future inference.
- [x] Deterministic synthetic tests cover GAP, DISCONT, format change, inferred drop, and nominal continuous flow.
- [x] Swift build passes.

### US-008: Implement live finalization

**Description:** As a recording caller, I need a deterministic way to stop live reliable capture without silently losing the encoder's final packets.

**Acceptance Criteria:**
- [x] Add `public func finalize(timeout: Duration = .seconds(5)) async throws` on `AudioSource`.
- [x] `finalize` calls `pipeline.sendEOS()` before stopping the pipeline.
- [x] If `sendEOS()` returns false, throw `GStreamerError.busError("Failed to send EOS event", source: "AudioSource.finalize", debug: nil)`.
- [x] Add `Bus.waitForEOS(timeout:) async throws` or an equivalent internal helper that waits for EOS or ERROR.
- [x] If Bus ERROR arrives before EOS, throw a `GStreamerError.busError` containing the parsed bus message.
- [x] If timeout expires before EOS or ERROR, throw `GStreamerError.busError("Timed out waiting for EOS during live reliable finalization", source: "AudioSource.finalize", debug: "timeout=<nanoseconds>")`.
- [x] `stop()` remains callable and keeps its existing immediate-stop behavior; it does not send EOS or guarantee encoder drain.
- [x] `finalize()` is the graceful shutdown path for reliable users, is safe to call more than once, and treats an already-stopped pipeline as a completed shutdown.
- [x] If `stop()` is called before `finalize()`, `finalize()` does not restart the pipeline and returns or throws according to the stopped terminal state without producing additional packets.
- [x] If `finalize()` completes before `stop()`, a later `stop()` is a no-op beyond preserving existing idempotent stop semantics.
- [x] Before calling `pipeline.stop()` on a successful EOS path, `finalize()` waits until the reliable iterator has consumed to `nil` or the iterator has been cancelled.
- [x] After `finalize()` completes successfully, any further iteration over the active reliable sequence immediately returns `nil`; no unconsumed tail packet may remain hidden in appsink.
- [x] Tests cover EOS success, Bus ERROR, timeout, and sendEOS failure.
- [x] Tests cover `stop()` before `finalize()`, `finalize()` before `stop()`, duplicate `finalize()` calls, and finalize/iterator tail-drain coordination.
- [x] Swift build passes.

### US-009: Document live reliable delivery

**Description:** As a library user, I need documentation that explains when to use live reliable delivery and what trade-offs each queue policy creates.

**Acceptance Criteria:**
- [x] DocC for `withReliableDelivery(...)` explains `.none`, `.upstream`, and `.downstream` using GStreamer's leak direction vocabulary.
- [x] DocC explains why the default `leaky: .none` favors zero silent queue drops when the consumer keeps up, and warns that slow consumers can cause source xruns or device-level loss outside GStreamer queue observability.
- [x] DocC for `reliablePackets()` states it is encoded live audio only in this phase.
- [x] DocC explains that raw live users should continue to use `buffers()` and that raw reliable buffers are future work.
- [x] Documentation states `packets()` remains realtime best-effort and may drop.
- [x] Documentation explains `stop()` versus `finalize(timeout:)`: `stop()` is immediate, while `finalize()` is the graceful EOS-drain path for reliable capture.
- [x] README or DocC example shows Opus live reliable opt-in, iteration, and `finalize(timeout:)`.
- [x] Documentation mentions VideoSource reliable delivery, fan-out, and recording convenience APIs as future work.
- [x] DocC generation succeeds when tooling is available, with no new content warnings.

### US-010: Add deterministic tests without physical capture hardware

**Description:** As a maintainer, I need CI-safe tests that exercise live reliable semantics without requiring a real microphone or webcam.

**Acceptance Criteria:**
- [x] Reliable live tests use deterministic synthetic live pipelines such as `audiotestsrc is-live=true`, controlled test hooks, or injected candidate descriptions.
- [x] No required CI test depends on physical microphone or webcam hardware.
- [x] Manual microphone/webcam smoke checks may be documented but are not required for CI pass/fail.
- [x] Tests verify nominal no-discontinuity flow under synthetic live input.
- [x] Tests verify slow-consumer behavior for `.downstream` and `.none` without relying on exact dropped counts.
- [x] Tests verify cancellation cleanup through observable handler/continuation probes.
- [x] Focused test suite passes under `swift test --filter Reliable` and `swift test --filter Audio`.

### US-011: Preserve existing public behavior

**Description:** As an existing user, I need this feature to be additive so current realtime and file/decode APIs continue to behave as before.

**Acceptance Criteria:**
- [x] `AudioSource.packets() -> AsyncStream<Buffer>` remains source-compatible and realtime lossy.
- [x] `AudioSource.buffers() -> AsyncStream<AudioBuffer>` remains source-compatible and realtime best-effort.
- [x] `AudioFileSource.reliablePackets() -> ReliablePackets<Buffer>` remains source-compatible.
- [x] No public `VideoSourceBuilder.withReliableDelivery(...)` is added in this phase.
- [x] No public `VideoSource.reliablePackets()` is added in this phase.
- [x] Static API tests verify the constraints above.
- [x] Full `swift test` passes when GStreamer system dependencies are available.

## Functional Requirements

- [x] **FR-1:** RFC-002 must be updated to remove `LiveSourceDeliveryPolicy` from the recommended API and to document the direct `QueueLeaky` + queue bounds decision.
- [x] **FR-2:** `AudioSourceBuilder` must expose exactly `withReliableDelivery(leaky:maxBuffers:maxBytes:maxTime:)` with defaults `.none`, `256`, `nil`, and `.seconds(2)`.
- [x] **FR-3:** Public reliable live configuration must reject `.raw` encoding, negative `maxTime`, and effectively unbounded queue bounds with the exact errors specified in US-002.
- [x] **FR-4:** Reliable live `AudioSource` pipelines must insert the configured `queue` after audio normalization and before the encoder.
- [x] **FR-5:** Reliable queue serialization must use `QueueLeaky.rawValue` and GStreamer's `0` disabled-limit convention for omitted or zero bounds.
- [x] **FR-6:** Reliable live appsink configuration must be `drop=false sync=false emit-signals=true enable-last-sample=false wait-on-eos=true max-buffers=1`.
- [x] **FR-7:** `AudioSource.reliablePackets()` must be throwing and must return `ReliablePackets<ReliablePacket<Buffer>>`.
- [x] **FR-8:** Calling `reliablePackets()` without reliable builder opt-in must throw the exact `GStreamerError.invalidArgument` specified in US-006.
- [x] **FR-9:** `ReliablePacket` and `Discontinuity` must use `UInt64?` nanosecond timestamps and the exact `Discontinuity.Kind` cases specified in US-004.
- [x] **FR-10:** Discontinuity detection must implement the exact signal mapping, caps equality, gap-duration formula, `droppedCount == nil` v1 behavior, and precedence specified in US-007.
- [x] **FR-11:** CGStreamerShim must expose the buffer flag access needed to detect GAP and DISCONT.
- [x] **FR-12:** `AudioSource.finalize(timeout:)` must send EOS, wait for Bus EOS or ERROR, coordinate iterator drain-or-cancel before stop, enforce timeout, and throw the exact errors specified in US-008.
- [x] **FR-13:** The reliable live bridge must reuse the Phase 1 continuation/cancellation approach and must never perform blocking sample pulls from async context.
- [x] **FR-14:** No public VideoSource reliable API is added in this phase.
- [x] **FR-15:** Existing realtime audio APIs and `AudioFileSource.reliablePackets()` remain source-compatible.

## Non-Goals (Out of Scope)

- Raw reliable live buffers for `AudioSource.buffers()`.
- Public `VideoSourceBuilder.withReliableDelivery(...)`.
- Public `VideoSource.reliablePackets()`.
- Tee/fan-out or per-branch queue policies.
- `record(to:)`, `record(for:)`, muxing, or file finalization convenience APIs.
- Public unbounded reliable live queue configuration.
- Appsink `buffer-list=true` handling.
- Renaming `QueueLeaky` cases or changing their raw values.
- Changing realtime `packets()` or `buffers()` default behavior.

## Design Considerations

- Use GStreamer's vocabulary directly. `QueueLeaky.none`, `.upstream`, and `.downstream` already match `queue leaky=0/1/2`.
- Keep queue policy at builder time. Live-source backpressure behavior must be decided before the pipeline is built.
- Default `leaky: .none` is intentional. It gives reliable callers a no-silent-queue-drop happy path when the consumer keeps up; slow consumers may block streaming threads and surface xruns instead of silently dropping queued data. Callers that prefer latency over completeness should explicitly pass `.downstream`.
- Keep the appsink bounded. Appsink `max-buffers=1` prevents a hidden post-encoder backlog from masking pressure at the configured queue.
- Use `enable-last-sample=false` to avoid retaining an extra sample outside the reliable iterator, and `wait-on-eos=true` so appsink cooperates with EOS drain while a reliable consumer is active.
- Keep time values consistent with existing API. `Buffer` already exposes `pts` and `duration` as `UInt64?` nanoseconds, so live reliable metadata should do the same.
- Prefer deterministic synthetic live tests over hardware tests. CI should not depend on microphone or webcam availability.

## Technical Considerations

- The existing `QueueLeaky` semantics and `Queue.leaky(maxBuffers:)` behavior have already been corrected by the queue semantics PRD; this PRD must build on those corrected meanings.
- The reliable live bridge should share implementation shape with `AudioFileReliablePacketSource`: signal callbacks, one pending continuation, non-blocking `try_pull_sample`, bus error observation, and cancellation cleanup.
- `Bus.waitForEOS(timeout:)` may be public if generally useful, or internal if the implementation wants to minimize API surface; implement it by consuming `Bus.messages(filter: [.eos, .error])` with timeout cancellation rather than blocking a Swift executor thread.
- Reliable live test hooks may be internal-only, following the existing `AudioFileSource` testing hook pattern.
- Negative `Duration` handling must happen before nanosecond conversion to avoid accidental unsigned overflow; prefer reusing or lifting the existing `Duration.nanosecondsForReliablePackets` conversion pattern rather than duplicating unchecked conversions.
- Encoder availability tests should follow existing conditional plugin conventions: if `opusenc` or AAC encoders are unavailable, skip only codec-specific tests with an explicit recorded reason and keep codec-independent reliable tests active.
- If DocC tooling or GStreamer system dependencies are unavailable locally, the implementation report must state the exact blocked verification instead of silently skipping required tests.

## Success Metrics

- `swift test --filter Reliable` passes.
- `swift test --filter Audio` passes.
- Static API tests pass and verify no `LiveSourceDeliveryPolicy` public API and no public VideoSource reliable API.
- Deterministic synthetic live tests cover nominal flow, GAP, DISCONT, format change, inferred drop, finalize success, finalize timeout, sendEOS failure, Bus ERROR, and cancellation cleanup.
- No required test depends on physical microphone or webcam hardware.
- DocC generation has no new content warnings when documentation tooling is available.
- Full `swift test` passes with GStreamer system dependencies installed.

## Resolved Questions

- **Policy API:** Use direct `QueueLeaky` plus bounds; do not add `LiveSourceDeliveryPolicy`.
- **Delivery scope:** v1 supports encoded live audio only (`Opus` and `AAC`).
- **Raw mode:** Reliable live delivery with `.raw` encoding is rejected at build time.
- **Video scope:** No public VideoSource reliable API is added in this phase.
- **Time type:** Use `UInt64?` nanoseconds; do not add public `ClockTime`.
- **Unsupported reliablePackets call:** Throw `GStreamerError.invalidArgument` with the exact message specified in US-006.
- **Discontinuity duration:** Represents the gap only: `nextPTS - (priorPTS + priorDuration)` when all values are available and non-underflowing.
- **Dropped count:** Reserved for future inference; v1 always returns `nil`.
- **Caps comparison:** Use `gst_caps_is_equal`, not caps string equality.
- **Finalization:** Use EOS send, Bus EOS/ERROR wait, iterator drain-or-cancel coordination, timeout, then stop.
- **Stop relationship:** `stop()` stays immediate; `finalize()` is the reliable graceful shutdown path; both are idempotent.
- **Unbounded config:** Public builder rejects effectively unbounded reliable queue configuration.
- **Appsink bound:** Reliable live appsink uses `max-buffers=1`.

## Open Questions

- What exact public API should VideoSource reliable delivery use in a later phase?
- Should tee/fan-out policies be configured per branch through a future branch builder?
- Should raw reliable live buffers use `ReliablePackets<ReliablePacket<AudioBuffer>>`, `ReliablePackets<ReliablePacket<Buffer>>`, or a separate API?
- Should a higher-level `record(to:for:)` API be layered on top of live reliable packets?
- Should appsink `buffer-list=true` be supported as a throughput optimization after v1?
- Should the QueueLeaky behavior fix, ADR-001 taxonomy work, RFC-002 PRD, and live reliable implementation be announced together in one release-note section?
