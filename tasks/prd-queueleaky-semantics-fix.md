# PRD: QueueLeaky Semantics Fix and RFC-002 Mapping Correction

## Introduction/Overview

The Swift `QueueLeaky` enum and its static helper `Queue.leaky(maxBuffers:)` describe their behavior in the **opposite direction** of GStreamer's actual `queue` element semantics. As a result:

- `Queue.leaky(maxBuffers:)` is documented as "drops old buffers" and "useful for live sources where you want to keep the most recent data", but its implementation passes `leaky: .upstream` (`leaky=1`), which in GStreamer means **drop new/incoming buffers** — the opposite of the documented intent.
- `RFC-002` repeats the same reversed mapping at line 196, mapping `.dropOldestPreservingLatency(maxBuffers:)` to `QueueLeaky.upstream` while describing it as "dropping stale queued buffers".

Authoritative GStreamer semantics:

- `leaky=1` (`upstream`) = drops **new (incoming)** buffers, keeps oldest queued.
- `leaky=2` (`downstream`) = drops **old (queued)** buffers, keeps newest.

This PRD fixes the documentation, the helper's runtime behavior, the impacted tests, and the RFC mapping, and discloses the helper change as a behavior bugfix in release notes. `rawValue`s and the public case names `.upstream`/`.downstream` are kept unchanged so they continue to mirror GStreamer's native vocabulary.

## Status

Last updated: 2026-05-09.

- Drafting: reviewed and revised.
- Implementation: completed in the current QueueLeaky semantics fix changes.
- Release notes: added in `CHANGELOG.md`.
- DocC tooling: Swift DocC plugin dependency added in `Package.swift` and
  resolved in `Package.resolved`.
- User stories: US-001 through US-006 are complete.
- Verification: `swift test --filter QueueLeakyBehaviorTests`,
  `swift test --filter ResultBuilderTests`,
  `swift test --filter PipelineElementTests`, `swift build`, and full
  `swift test` passed.
  `swift package generate-documentation --target GStreamer --warnings-as-errors`
  also runs and generates the documentation archive. The remaining console
  warnings are SwiftPM/pkg-config `-Wl,-rpath` warnings from the local
  GStreamer install, not DocC content warnings.
- Related work:
  - `Package.swift` / `Package.resolved` (Swift DocC plugin dependency).
  - `Sources/GStreamer/Pipelines/Elements/Queue.swift` (enum + static helper).
  - `docs/RFCs/RFC-002-live-source-reliable-delivery.md` (Queue Policy Contract section).
  - `CHANGELOG.md` (already present with a `## Next` section).

## Goals

- Make `QueueLeaky` doc-comments accurately describe GStreamer's `leaky=1`/`leaky=2` runtime behavior.
- Make `Queue.leaky(maxBuffers:)` runtime behavior match its own DocC promise ("drops old buffers", "keep the most recent data") by switching its internal mapping to `.downstream`.
- Keep all enum `rawValue`s, public case names (`.none`, `.upstream`, `.downstream`), and existing serialization (`leaky=N`) unchanged so direct enum users keep their compile-time and runtime contract.
- Update `RFC-002` so the policy-to-`QueueLeaky` mapping table reflects GStreamer reality and stays consistent with the post-fix Swift code.
- Add release notes describing the `Queue.leaky(...)` behavior reversal as a bugfix and listing the affected call sites.
- Add a behavioral test that runs a real GStreamer pipeline and verifies that `leaky=2` keeps newest and drops oldest (and conversely for `leaky=1`), so the documented semantics cannot silently regress to the old reversed wording again.

## User Stories

### US-001: Fix `QueueLeaky` doc-comments

**Description:** As a library user reading `QueueLeaky`, I need each case's doc-comment to describe what GStreamer actually does at that `leaky=N` value, so I can pick the right case from the symbol docs alone.

**Acceptance Criteria:**
- [x] `case none = 0` doc-comment reads as: "Not leaky — block the upstream producer when full." Equivalent to GStreamer `leaky=0`.
- [x] `case upstream = 1` doc-comment reads as: "Leaky on the upstream side: drop **newest (incoming)** buffers when full; keeps the oldest queued buffers. Equivalent to GStreamer `leaky=1`."
- [x] `case downstream = 2` doc-comment reads as: "Leaky on the downstream side: drop **oldest (queued)** buffers when full; keeps the newest. Equivalent to GStreamer `leaky=2`."
- [x] No `rawValue` is changed.
- [x] No public case is renamed or removed.
- [x] DocC builds without new warnings.
- [x] `swift build` passes.

### US-002: Fix `Queue.leaky(maxBuffers:)` to match its docs

**Description:** As a caller of `Queue.leaky(maxBuffers:)` who wants a "drop old, keep newest" live-source queue, I need the helper's runtime behavior to match what its DocC promises, instead of producing the opposite GStreamer policy.

**Acceptance Criteria:**
- [x] In `Sources/GStreamer/Pipelines/Elements/Queue.swift`, change `Queue.leaky(maxBuffers:)` to construct `Queue(maxBuffers: maxBuffers, leaky: .downstream)`.
- [x] The resulting pipeline string contains `leaky=2`, not `leaky=1`.
- [x] Doc-comment of `Queue.leaky(maxBuffers:)` is rewritten to describe only the current behavior: "Create a leaky queue that drops the **oldest queued** buffers when full so the consumer always sees the most recent live data. Useful for live sources where latency must be preserved over completeness. Equivalent to GStreamer `leaky=2`."
- [x] Historical behavior and migration impact are documented in `CHANGELOG.md`, not in the long-term DocC comment.
- [x] No new public symbol is introduced; no existing public symbol is renamed or removed.
- [x] `swift build` passes.

### US-003: Update string-assertion tests for `Queue.leaky(...)`

**Description:** As a maintainer, I need the tests that currently assert `Queue.leaky(...)` produces `leaky=1` to assert `leaky=2` instead, so the test suite locks in the corrected mapping.

**Acceptance Criteria:**
- [x] In `Tests/SwiftGStreamerTests/ResultBuilderTests.swift`, the `@Test("Queue.leaky static method")` block (around lines 407–418) asserts `pipeline.pipeline.contains("leaky=2")`.
- [x] In `Tests/SwiftGStreamerTests/PipelineElementTests.swift`, the `@Test("Queue leaky")` block (around lines 127–132) asserts `queue.pipeline.contains("leaky=2")`.
- [x] Test functions, names, and unrelated assertions are not otherwise modified.
- [x] The two existing direct-enum smoketests that already assert `.upstream` → `leaky=1` and `.downstream` → `leaky=2` (`ResultBuilderTests.swift` ~line 70 `untypedQueue` and ~line 365 `complexUntypedPipeline`) remain **unchanged**, since they correctly verify the raw enum-to-string serialization and that mapping is unaffected by this PRD.
- [x] `swift test --filter ResultBuilderTests` and `swift test --filter PipelineElementTests` pass.

### US-004: Add a deterministic behavioral test that verifies real drop direction

**Description:** As a maintainer, I need at least one runtime test that drives a real GStreamer pipeline at `leaky=1` and `leaky=2` and inspects which buffers survived, so the documented semantics are protected against future doc-only regressions.

**Acceptance Criteria:**
- [x] Add a Swift Testing case (working name `QueueLeakyBehaviorTests`) in `Tests/SwiftGStreamerTests/`.
- [x] The test uses an `appsrc`-driven pipeline with deterministic tags in each pushed buffer, using either the buffer PTS or the first payload byte as the tag value.
- [x] The queue under test explicitly disables unrelated queue limits: `max-size-buffers=<N> max-size-bytes=0 max-size-time=0 leaky=<1-or-2>`, so the test exercises the buffer-count limit only.
- [x] The downstream gate is installed before the measured appsrc pushes, and the test waits for confirmation that the gate is active before pushing tagged buffers. A drained priming buffer is pushed before gate installation to establish stream-start/segment flow.
- [x] The downstream gate prevents the queue from draining before overflow. Prefer an idle+blocking pad probe via `Pad.addProbe(type: [.idle, .blocking])` on the queue's `src` pad or an equivalent deterministic mechanism; do not use a plain `.buffer + .blocking` probe that only activates after the first buffer has already left the queue.
- [x] If the chosen gate can hold one in-flight buffer outside the queue, the test records that buffer separately and excludes it from the post-overflow survivor-set assertion, so `.downstream` is not falsely failed by the pre-overflow first buffer.
- [x] The test records evidence that overflow pressure actually occurred before asserting semantics: more than `<N>` buffers are pushed while downstream is blocked, and the observed survivor set contains fewer tags than the pushed set.
- [x] The test runs the same scenario under each of:
  - `leaky=1` (`.upstream`) — expects the **earliest** tags to survive and the latest to be dropped.
  - `leaky=2` (`.downstream`) — expects the **latest** tags to survive and the earliest to be dropped.
- [x] Survived-tags assertions match the surviving set structurally, such as requiring `.upstream` survivors to include the minimum pushed tag and exclude the maximum pushed tag, and `.downstream` survivors to include the maximum pushed tag and exclude the minimum pushed tag. Do not assert an exact dropped count.
- [x] The test does **not** use a silent early-return skip. It should run like the existing AppSource/AppSink smoke tests when GStreamer is installed. If a CI runner lacks GStreamer system dependencies, the implementation PR reports that verification as blocked or failed rather than silently skipping the test.
- [x] `swift test --filter QueueLeakyBehaviorTests` passes locally with GStreamer dependencies installed.

### US-005: Correct RFC-002 mapping (line 196)

**Description:** As a reader of `RFC-002`, I need the policy-to-`QueueLeaky` mapping to match GStreamer's actual leak direction so the RFC does not propagate the same reversed mapping into future implementation work.

**Acceptance Criteria:**
- [x] In `docs/RFCs/RFC-002-live-source-reliable-delivery.md`, line 196 is rewritten to map `.dropOldestPreservingLatency(maxBuffers:)` to `QueueLeaky.downstream` with bounded queue, with a sentence noting that this corresponds to GStreamer `leaky=2`, drops the oldest queued buffer, and keeps the consumer on the newest live frames.
- [x] No other policy in that mapping list is silently changed; `.blockOnFull(...)` and `.unboundedQueue` rows remain as is.
- [x] If RFC-002 has any inline example or prose elsewhere that says "leaky upstream drops old" or similar, those occurrences are corrected in the same edit.
- [x] RFC status line is left as `Proposed` unless release planning explicitly promotes it; this PRD does not change RFC status.
- [x] Markdown-only change is reviewed with `rg "QueueLeaky\\.upstream" docs/RFCs/RFC-002-live-source-reliable-delivery.md` to confirm the drop-oldest mapping no longer points at `.upstream`.

### US-006: Add CHANGELOG entry as a behavior bugfix

**Description:** As a downstream caller of `Queue.leaky(...)`, I need release notes to clearly tell me that the helper used to call `leaky=upstream` (drop newest), now calls `leaky=downstream` (drop oldest), and what to do if I depended on the prior behavior.

**Acceptance Criteria:**
- [x] Add an entry under the existing `## Next` section of `CHANGELOG.md`.
- [x] Add a `### Bugfixes` subsection under `## Next` if it is not already present.
- [x] Entry is placed under `### Bugfixes`.
- [x] Entry states: previous `Queue.leaky(maxBuffers:)` set `leaky=1` (`.upstream`) which actually drops **newest** buffers, contradicting the helper's own documentation. After this fix it sets `leaky=2` (`.downstream`) and drops the **oldest** buffers, matching the documentation and live-source intent.
- [x] Entry tells callers who relied on "drop newest" behavior to instead use the explicit `Queue(maxBuffers:, leaky: .upstream)` initializer (semantics unchanged).
- [x] Entry links to `docs/RFCs/RFC-002-live-source-reliable-delivery.md` and notes the matching mapping correction in that RFC.
- [x] Entry calls out that `QueueLeaky` enum cases and `rawValue`s are **unchanged** (no source-compatibility break for direct enum users).
- [x] Markdown-only change is reviewed for placement under `## Next`.

## Functional Requirements

- **FR-1:** `QueueLeaky.none`, `.upstream`, and `.downstream` keep their current `rawValue`s `0`, `1`, and `2`.
- **FR-2:** Public case names `none`, `upstream`, `downstream` are not renamed.
- **FR-3:** `QueueLeaky` doc-comments must describe GStreamer's actual drop direction for each case (per US-001).
- **FR-4:** `Queue.leaky(maxBuffers:)` must construct a `Queue` with `leaky: .downstream` (`leaky=2` in serialized form).
- **FR-5:** `Queue.leaky(maxBuffers:)` doc-comment must accurately describe drop-oldest, keep-newest semantics and reference GStreamer `leaky=2`.
- **FR-6:** Tests that exercise `Queue.leaky(maxBuffers:)` must assert `leaky=2`.
- **FR-7:** Direct-enum tests asserting `.upstream → leaky=1` and `.downstream → leaky=2` must remain unchanged.
- **FR-8:** A new behavioral test must verify that a bounded queue with deterministic overflow drops the oldest buffers under `.downstream` and the newest buffers under `.upstream`.
- **FR-9:** RFC-002 line 196 must map `.dropOldestPreservingLatency(maxBuffers:)` to `QueueLeaky.downstream`, with a one-liner referencing GStreamer `leaky=2`.
- **FR-10:** `CHANGELOG.md` must contain a Bugfix entry describing the `Queue.leaky(maxBuffers:)` runtime change, suggested workaround for any caller that depended on the old reversed behavior, and a link to RFC-002.
- **FR-11:** No public API surface is added or removed by this PRD (no aliases, no new helpers, no rename).
- **FR-12:** This PRD does not require a lint command unless the implementation PR discovers and documents a repo-local lint command. Required verification is `swift build`, the focused tests listed below, full `swift test`, and optional DocC generation.

## Non-Goals (Out of Scope)

- **NG-1:** Adding readability aliases such as `dropNewest`/`dropOldest` static properties on `Queue` or convenience cases on `QueueLeaky`. Considered and rejected to keep API surface stable; revisit only if RFC-002 implementation introduces a `LiveSourceDeliveryPolicy` enum that makes such aliases redundant anyway.
- **NG-2:** Renaming or removing `QueueLeaky.upstream` / `QueueLeaky.downstream` cases. Their names mirror GStreamer's official enum and must stay aligned.
- **NG-3:** Implementing `LiveSourceDeliveryPolicy`, `withReliableDelivery(policy:)`, or any other RFC-002 API surface. This PRD only fixes the mapping table inside the RFC document.
- **NG-4:** Promoting RFC-002 from `Proposed` to `Accepted`.
- **NG-5:** Changing AppSink configuration, `packets()` semantics, or any pipeline element other than `Queue.leaky(...)`.
- **NG-6:** Restructuring `CHANGELOG.md` beyond adding a `### Bugfixes` subsection under `## Next` if needed.
- **NG-7:** Adding `LocalizedError` conformance, error taxonomy changes, or anything overlapping with ADR-001 / RFC-001 / RFC-002 follow-up work.
- **NG-8:** Adding silent test skips or environment-gated early returns for the new queue behavior test.

## Design Considerations

- **GStreamer truth wins.** The integer values `0/1/2` are defined by GStreamer and are not negotiable. Any Swift documentation or higher-level wrapper that disagrees with GStreamer's runtime behavior is a Swift-side bug, not a design alternative.
- **Case names track GStreamer's vocabulary.** `.upstream` and `.downstream` are deliberately named after GStreamer's `LEAK_UPSTREAM` / `LEAK_DOWNSTREAM`. This makes mental translation between Swift code and `gst-launch` strings trivial and cuts off a class of "renamed in Swift but reversed in `leaky=N`" bugs in the future.
- **The helper expresses intent, not raw `leaky=N`.** `Queue.leaky(maxBuffers:)` exists precisely to spare callers from picking the right `LEAK_*` direction. Its documentation already commits to a specific intent ("drops old", "keep most recent data"), so its implementation must follow the documentation. The enum is the low-level truth; the helper is the high-level intent.
- **Behavior reversal must be loud.** Even though no signature changes, the runtime behavior of `Queue.leaky(maxBuffers:)` flips. This must be released as a Bugfix entry, not as an internal cleanup, so callers who happened to depend on the prior (reversed) behavior have a clear migration note.
- **RFC-002 stays Proposed.** This PRD does not implement RFC-002; it only fixes the mapping table inside it so the RFC, when later promoted, does not lock in the reversed mapping.

## Technical Considerations

- Primary source change: `Sources/GStreamer/Pipelines/Elements/Queue.swift` — update three doc-comments on `QueueLeaky` cases, update the doc-comment + body of `Queue.leaky(maxBuffers:)` (one-line body change `.upstream` → `.downstream`).
- Primary test changes:
  - `Tests/SwiftGStreamerTests/ResultBuilderTests.swift` — `@Test("Queue.leaky static method")` only.
  - `Tests/SwiftGStreamerTests/PipelineElementTests.swift` — `@Test("Queue leaky")` only.
  - New test file (working name `Tests/SwiftGStreamerTests/QueueLeakyBehaviorTests.swift`) for US-004.
- The behavioral test should use the existing pad probe API in `Sources/GStreamer/Pad.swift` (`ProbeType.blocking`, `ProbeType.idle`, and `addProbe(type:callback:)`) if it uses a pad-probe gate.
- Documentation change: `docs/RFCs/RFC-002-live-source-reliable-delivery.md` line 196.
- CHANGELOG change: add a `### Bugfixes` subsection under `## Next` if needed, then add the queue behavior entry there. Do not restructure other sections.
- No repo lint command is currently part of the required workflow. If the implementation PR discovers a valid lint command, it may run it and report the result as extra verification.
- Verification commands:
  - `swift build`
  - `swift test --filter QueueLeakyBehaviorTests`
  - `swift test --filter ResultBuilderTests`
  - `swift test --filter PipelineElementTests`
  - `swift test`
  - `swift package generate-documentation` if the DocC plugin is available locally.
- If GStreamer system dependencies are unavailable, report the Swift build/test verification as blocked or failed with the exact reason. Do not silently skip the new behavior test.
- If DocC tooling is unavailable, report the skipped DocC verification with the exact reason, mirroring the convention used by the ADR-001 PRD.

## Success Metrics

- `rg "leaky:\s*\.upstream" Sources/GStreamer/Pipelines/Elements/Queue.swift` returns no matches inside `Queue.leaky(maxBuffers:)` after the change.
- `rg "leaky=1" Tests/SwiftGStreamerTests/PipelineElementTests.swift Tests/SwiftGStreamerTests/ResultBuilderTests.swift` returns matches **only** in the direct-enum smoketests (`.upstream` cases), never in the `Queue.leaky(maxBuffers:)` tests.
- `rg "QueueLeaky\.upstream" docs/RFCs/RFC-002-live-source-reliable-delivery.md` returns no matches in the `dropOldestPreservingLatency` mapping bullet after the edit (it appears, if at all, only inside Option-listing prose).
- `swift test` passes locally with GStreamer dependencies present; the new behavioral test passes deterministically across at least three consecutive local runs.
- The new behavioral test explicitly disables queue byte/time limits and records that overflow pressure occurred before asserting survivor tags.
- DocC generation introduces zero new warnings when DocC tooling is available.

## Open Questions

- **RFC-002 prose audit beyond line 196.** The mapping bullet at line 196 is the only known offender, but if the implementation PR finds other RFC-002 prose that says "leaky upstream drops old" or similar, those occurrences should be corrected in the same edit (already covered by US-005's third acceptance bullet); this PRD does not pre-enumerate them.
- **Coordination with RFC-002 implementation PRD.** When a follow-up PRD lands `LiveSourceDeliveryPolicy` and `withReliableDelivery(policy:)`, that PRD should reference this fix so its mapping bullet matches the corrected RFC and the corrected `QueueLeaky` docs.
