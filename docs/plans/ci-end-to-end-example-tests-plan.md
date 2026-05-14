# CI End-to-End Example Tests Plan

## Summary

Add a dedicated Swift Testing suite for two CI-safe end-to-end GStreamer
example flows:

- finite `videotestsrc` frames delivered through `appsink`;
- deterministic `appsrc` frames accepted by a downstream `fakesink` and
  completed by EOS.

The change is tests-only. It does not alter public API, package targets,
examples, README, DocC, or CI workflow configuration.

## Problem

The package has focused unit and smoke tests for `AppSink`, `AppSource`,
timestamps, and bus messages, but it does not have one deliberately named
CI-facing suite that proves the smallest example-style app boundary flows run
end-to-end on the same GitHub Actions jobs that build the package.

## Goals

- Add exactly two CI-safe end-to-end example tests.
- Cover both app boundary directions:
  - GStreamer source to Swift via `appsink`;
  - Swift to GStreamer via `appsrc`.
- Use only synthetic finite sources and sinks so the tests require no camera,
  microphone, display, file system media, network, or platform device.
- Use Swift Testing conventions already present in the repository.
- Fail normally when GStreamer runtime dependencies are missing; do not add
  silent skips.
- Keep the suite suitable for the existing serial CI command:
  `swiftly run swift test --no-parallel`.

## Non-Goals

- Do not add `audiotestsrc ! appsink` in this pass; existing audio tests cover
  the audio appsink path.
- Do not add README, DocC, executable examples, package target, or CI workflow
  changes.
- Do not change public API or source behavior.
- Do not introduce device-backed, display-backed, network-backed, or
  long-running media pipelines.

## Current Behavior

Existing tests cover adjacent behavior:

- `AppSinkSmokeTests` pulls frames from `videotestsrc ! appsink`.
- `TimestampTests` checks `videotestsrc` timestamps and an `appsrc ! appsink`
  timestamp roundtrip.
- `AppSourceTests` pushes frames through `appsrc ! fakesink` and waits for EOS.
- `Bus.waitForEOSOrError()` throws on pipeline error and returns on EOS.

Those tests are useful, but their intent is spread across API-specific suites
rather than a small CI end-to-end example suite.

## Proposed Behavior

Add `Tests/SwiftGStreamerTests/CIEndToEndExampleTests.swift` with:

- `@Suite("CI End-to-End Examples", .timeLimit(.minutes(1)))`;
- `init() throws { try GStreamer.initialize() }`;
- one async test for a finite `videotestsrc ! appsink` example;
- one async test for a deterministic `appsrc ! fakesink` example.

### `videotestsrc ! appsink`

Use this pipeline:

```text
videotestsrc num-buffers=3 !
video/x-raw,format=BGRA,width=16,height=16,framerate=30/1 !
appsink name=sink sync=false drop=false max-buffers=3
```

The test should:

- start the pipeline and stop it in `defer`;
- start a bounded EOS/error bus wait before or while the pipeline runs;
- pull through `AppSink.frames()` inside a local timeout and drain the finite
  sequence to completion;
- observe exactly three frames from the finite source;
- assert each pulled frame has non-empty bytes and exactly `16 * 16 * 4`
  bytes;
- assert at least one frame reports parsed `width == 16`, `height == 16`, and
  `format == .bgra`;
- await bus EOS through `waitForEOSOrError()` so pipeline errors fail the test;
- not depend on a display device or real-time scheduling.

### `appsrc ! fakesink`

Use this pipeline:

```text
appsrc name=src is-live=false format=time !
video/x-raw,format=BGRA,width=2,height=2,framerate=30/1 !
identity name=tap !
fakesink sync=false
```

The test should:

- configure the `AppSource` caps to match the pipeline caps;
- call `setLive(false)`;
- attach a buffer-counting pad probe to `identity name=tap` so the test
  observes downstream delivery, not only push return values;
- start the pipeline and stop it in `defer`;
- push three deterministic `2x2` BGRA frames with PTS and duration;
- call `endOfStream()`;
- await `pipeline.bus.waitForEOSOrError()` through a bounded test helper;
- assert the downstream probe observed exactly three buffers;
- throw or fail on pipeline bus error.

## Affected Modules

- `Tests/SwiftGStreamerTests/CIEndToEndExampleTests.swift`
- `docs/plans/ci-end-to-end-example-tests-plan.md`
- `docs/bdd/ci-end-to-end-example-tests.feature`
- review summary artifacts under `docs/plans/`

## Public API and Interface Changes

None.

## Data Model Changes

None.

## Lifecycle and State Changes

The tests create short-lived pipelines, call `play()`, then call `stop()` in
`defer`. The `appsrc` test sends EOS through `AppSource.endOfStream()` and waits
for bus EOS or ERROR.

## Error Handling

- Pipeline construction and state transition errors propagate through `throws`.
- `waitForEOSOrError()` converts bus ERROR messages to `GStreamerError`.
- A small local timeout helper prevents a stuck pipeline from consuming the
  suite-wide one-minute limit before producing diagnostics.

## Compatibility

The tests use GStreamer elements provided by core/base plugin installations used
by the current CI setup: `videotestsrc`, `appsink`, `appsrc`, `identity`, and
`fakesink`. They use Swift 6.3.1-compatible Swift Testing patterns and do not
raise platform minimums.

## Observability

The suite name and test names should make CI output identify these as end-to-end
example checks. Assertions report frame counts, byte counts, parsed caps, and
downstream buffer delivery.

## Safety and Data Integrity

The tests use small in-memory buffers and synthetic media. They do not access
devices, user files, network resources, or persistent state.

## BDD Scenario Mapping

- Scenario: CI pulls finite synthetic video frames from an app sink.
  - Formal test: `videoTestSourceFramesReachAppSink()`.
  - Verifies frame count, byte size, and parsed video metadata.
- Scenario: CI pushes deterministic Swift video frames into a GStreamer sink.
  - Formal test: `appSourceFramesReachFakeSinkAndEOS()`.
  - Verifies downstream buffer delivery and clean EOS.

## Empty-Test Skeleton Plan

Create `Tests/SwiftGStreamerTests/CIEndToEndExampleTests.swift` with an empty
Swift Testing suite containing two async throwing test functions and only
Given/When/Then comments inside each function. Verify the skeleton contains no
assertions, setup logic, fixtures, helpers, executable code, or production
logic before writing formal tests.

## Formal Test Strategy

After the empty checkpoint is verified, replace the skeleton bodies with formal
Swift Testing code:

- use `#expect` for assertions and `#require` for dependent values;
- use a private local timeout helper for frame-drain and EOS waits;
- use a small thread-safe probe counter if the pad probe can run off the test
  task;
- run `swiftly run swift --version`;
- run `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`;
- run `swiftly run swift test --filter CIEndToEndExampleTests` as the focused
  check;
- run `swiftly run swift test --no-parallel` when dependencies are available.

Because these are additive tests for already-supported APIs, a targeted red run
after formal test creation may pass if existing source behavior already
satisfies the new specification. That outcome is acceptable for this tests-only
request and should be reported explicitly.

## Implementation Sequence

1. Add this plan and the Gherkin feature file.
2. Obtain plan review with `Verdict: No Findings`.
3. Add and verify the empty Swift Testing skeleton.
4. Fill in formal tests only after the empty checkpoint.
5. Run `swiftly run swift --version`.
6. Run `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`.
7. Run the focused test command.
8. Make no source changes unless the formal tests expose a behavior defect.
9. Run spec compliance review.
10. Run code-quality review.
11. Run final verification and completion audit.

## Risks

- `AppSink.frames()` may not populate parsed dimensions on the first frame, so
  the appsink test should assert that parsed metadata is observed at least once
  rather than requiring every frame to have metadata.
- Waiting for EOS without a local timeout can hide failures behind the suite
  time limit.
- The new suite overlaps adjacent smoke tests, so assertions must remain
  end-to-end focused rather than duplicating existing create/not-found tests.

## Acceptance Criteria

- `docs/bdd/ci-end-to-end-example-tests.feature` exists and maps to the test
  suite.
- `Tests/SwiftGStreamerTests/CIEndToEndExampleTests.swift` contains exactly two
  formal tests for the approved scenarios.
- The appsink test observes three finite BGRA frames with exact byte counts and
  parsed metadata, drains the finite stream through a bounded wait, and observes
  bus EOS without pipeline error.
- The appsrc test pushes three deterministic BGRA frames, observes three
  downstream buffers, and reaches EOS without bus error.
- No public API, package target, CI workflow, README, DocC, executable example,
  or production source change is introduced unless a defect is discovered and
  explicitly documented.
- `swiftly run swift test --filter CIEndToEndExampleTests` passes when
  GStreamer dependencies are available.
- `swiftly run swift test --no-parallel` passes or any blocker is documented.

## Assumptions

- CI and local verification environments have GStreamer 1.20+ development
  headers and runtime plugins available through `pkg-config`.
- The existing `AppSink`, `AppSource`, `Pipeline`, `Element`, `Pad`, and `Bus`
  APIs are sufficient for this tests-only change.
