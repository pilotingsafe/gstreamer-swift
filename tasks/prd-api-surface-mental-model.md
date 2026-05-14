# PRD: API Surface Mental Model and Documentation Cleanup

## Introduction/Overview

GStreamer for Swift v0.1 exposes several useful public surfaces in one package:
low-level wrappers, source and sink builders, an experimental typed pipeline DSL,
best-effort streams, reliable live packets, reliable file packets, a pull-based
bus sequence, and compatibility bus streams. README, `APIContract.md`, and
`docs/v0.1-scope.md` already describe these layers, but users still need to read
multiple documents to understand which API they should start with and which
behavioral contract applies.

This PRD defines post-v0.1 documentation-only cleanup for the package's API
mental model. It treats the current surface as acceptable for v0.1 and plans a
clearer "core wrapper plus optional convenience layers" story without changing
Swift source code, public API, package products, or module names.

## Status

Last updated: 2026-05-14.

- PRD: proposed future documentation work.
- Implementation: not started.
- Scope: documentation and planning only.
- Related documents: `README.md`, `Sources/GStreamer/Documentation.docc/APIContract.md`,
  `docs/v0.1-scope.md`, `tasks/prd-bus-drainer-dispatcher.md`.

## Goals

- Make the recommended API entry point clear for common user intents.
- Let users understand the core wrapper contract without reading every
  convenience or experimental API first.
- Label convenience, experimental, reliable-delivery, and compatibility APIs
  consistently across README and DocC.
- Preserve the v0.1 compatibility promise: existing public APIs remain available
  and source-compatible.
- Record future API cleanup directions, such as naming convergence,
  compatibility positioning, namespace evaluation, or package-product
  evaluation, without committing to breaking changes.

## User Stories

### US-001: Add a Recommended Entry Path

**Description:** As a new user, I want README to show which API I should start
with so that I can choose a path without understanding every public type first.

**Acceptance Criteria:**
- [ ] README includes a "Which API should I start with?" or equivalent section.
- [ ] The section maps common intents to recommended APIs:
  direct GStreamer control to `Pipeline`/`Element`, frame pulling to `AppSink`,
  data pushing to `AppSource`, simple capture/playback to builders, reliable
  packet delivery to reliable APIs, and bus ownership to bus APIs.
- [ ] The section appears before detailed examples that introduce convenience
  layers.
- [ ] Documentation-only verification reads the changed README back.

### US-002: Clarify the Core Wrapper Contract

**Description:** As a GStreamer-experienced user, I want the low-level wrappers
to remain clearly identified as the core contract so that I can choose direct
control when I need precise GStreamer behavior.

**Acceptance Criteria:**
- [ ] README and `APIContract.md` identify `Pipeline`, `Element`, `Bus`,
  `AppSink`, `AppSource`, `Buffer`, `AudioBufferSink`, `AudioBuffer`, and
  `VideoFrame` as the core low-level wrapper surface.
- [ ] The docs state that this core surface stays close to GStreamer ownership,
  bus consumption, and backpressure behavior.
- [ ] The docs avoid implying that convenience builders replace the core
  wrappers.
- [ ] Documentation-only verification reads the changed files back.

### US-003: Label Optional Convenience Layers

**Description:** As a convenience-layer user, I want source/sink builders and
reliable delivery APIs labeled by scope and guarantees so that I do not assume
they are the stable foundation of the package.

**Acceptance Criteria:**
- [ ] README and DocC consistently label `AudioSource`, `VideoSource`,
  `AudioSink`, and `AudioFileSource` as convenience builders over the lower-level
  wrappers.
- [ ] Reliable live packet delivery is labeled as encoded-audio, non-core, and
  not indefinitely lossless under sustained slowness.
- [ ] Reliable file packet delivery is labeled as finite file/decode delivery
  with repeatable, consumer-driven sequences.
- [ ] Best-effort streams are described separately from reliable streams.
- [ ] Documentation-only verification reads the changed files back.

### US-004: Position Compatibility and Experimental APIs

**Description:** As a maintainer, I want compatibility APIs and experimental APIs
labeled consistently so that future cleanup does not surprise users.

**Acceptance Criteria:**
- [ ] `Bus.messages(filter:)`, `Bus.errors()`, `Bus.warnings()`, and
  `Bus.stateChanges()` are documented as compatibility or simple convenience
  APIs over the same destructive bus queue.
- [ ] `Bus.messageSequence(filter:)` remains documented as the preferred
  low-level single-drainer path for explicit bus ownership.
- [ ] The typed pipeline DSL is consistently labeled experimental and non-core.
- [ ] The docs do not recommend direct multi-observer bus consumption; they
  point to future dispatcher work or one-owner guidance instead.
- [ ] Documentation-only verification reads the changed files back.

### US-005: Record Future API Cleanup Options

**Description:** As a future implementer, I want a documented cleanup backlog so
that naming, recommended paths, compatibility positioning, and possible
namespace or product separation can be evaluated deliberately.

**Acceptance Criteria:**
- [ ] A future-cleanup section records naming convergence as a possible maturity
  task without requiring immediate renames.
- [ ] A future-cleanup section records compatibility API positioning as a
  possible maturity task without requiring immediate deprecations.
- [ ] A future-cleanup section records namespace or SwiftPM product separation
  as an evaluation topic without changing `Package.swift`.
- [ ] The cleanup notes reference related future work such as a bus drainer or
  dispatcher when relevant.
- [ ] Documentation-only verification reads the changed files back.

## Functional Requirements

- **FR-1:** The documentation must define one recommended entry path for each
  common user intent: direct GStreamer control, frame pulling, data pushing,
  simple capture/playback, reliable packet delivery, and bus ownership.
- **FR-2:** The documentation must preserve the v0.1 core wrapper list:
  `Pipeline`, `Element`, `Bus`, `AppSink`, `AppSource`, `Buffer`,
  `AudioBufferSink`, `AudioBuffer`, and `VideoFrame`.
- **FR-3:** The documentation must call source and sink builders convenience
  layers over the lower-level wrappers.
- **FR-4:** The documentation must distinguish best-effort streams from reliable
  delivery APIs.
- **FR-5:** The documentation must distinguish reliable live delivery from
  reliable file/decode delivery.
- **FR-6:** The documentation must label the typed pipeline DSL as experimental
  and non-core.
- **FR-7:** The documentation must describe `Bus.messages(filter:)` and bus
  convenience streams as compatibility or simple convenience APIs, not as the
  recommended multi-observer model.
- **FR-8:** The documentation must keep direct bus APIs under the one-active-
  drainer rule unless a future dispatcher owns the bus.
- **FR-9:** The documentation must record future API cleanup options without
  requiring source-breaking changes.
- **FR-10:** The documentation work must not change Swift source files,
  `Package.swift`, public API names, package products, module names, examples'
  runtime behavior, or tests.

## Non-Goals (Out of Scope)

- No Swift source changes.
- No public API renames.
- No deprecations.
- No `Package.swift` changes.
- No new SwiftPM products or module split.
- No namespace changes.
- No bus drainer or dispatcher implementation.
- No change to current stream, packet, bus, or builder behavior.
- No promise that future cleanup will be source-compatible; this PRD only
  records options for later evaluation.

## Design Considerations

- Prefer one short decision path near the top of README over making users infer
  recommendations from many examples.
- Use consistent labels across README, DocC, and scope docs:
  "core low-level wrapper", "convenience builder", "delivery contract",
  "experimental typed DSL", and "compatibility API".
- Keep wording neutral: current v0.1 surface is acceptable, but the mental model
  should become easier to learn.
- Avoid hiding GStreamer semantics. The core wrapper should still be described
  as close to GStreamer ownership, bus, and backpressure behavior.
- Avoid presenting future namespace or product separation as a committed design.

## Technical Considerations

- This is documentation-only work. Use normal text edits and avoid touching
  generated files unless a documentation tool explicitly requires them.
- If DocC files are edited, run DocC generation when tooling and system
  dependencies are available.
- For documentation-only changes, read the changed files back and run
  `git diff --check`.
- Do not run `swift build` or `swift test` for this PRD's implementation unless
  a later documentation change alters behavioral documentation enough to justify
  it.
- Keep future API cleanup notes aligned with `tasks/prd-bus-drainer-dispatcher.md`
  and ADR-002 bus ownership language.

## Success Metrics

- A new user can identify the recommended starting API for direct pipeline
  control, capture, playback, reliable packet delivery, and bus consumption from
  README before reaching detailed examples.
- `APIContract.md` remains the detailed contract, but README and DocC provide
  enough guidance that users do not need it as the first stop.
- Core, convenience, experimental, reliable-delivery, and compatibility labels
  are consistent across touched docs.
- Future cleanup items are recorded without changing source compatibility.
- Documentation-only verification passes with `git diff --check`.

## Open Questions

- Should the README decision path be a table, a short bullet list, or a compact
  flowchart-style section?
- Should future API cleanup notes live in README, `docs/v0.1-scope.md`, a new
  ADR, or a follow-up task document?
- Should compatibility API language use the exact word "compatibility" for all
  legacy-like APIs, or should some be called "simple convenience" APIs instead?
- Should namespace or SwiftPM product separation be discussed only in task docs,
  or also mentioned in user-facing documentation?
