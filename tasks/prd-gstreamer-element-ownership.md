# PRD: GStreamer Element Ownership Fix

## Introduction

Before this fix, SwiftGStreamer emitted GStreamer critical logs in dynamic-element scenarios:

```text
Trying to dispose object "fakesink67", but it still has a parent "pipeline133".
You need to let the parent manage the object instead of unreffing the object directly.
```

With `G_DEBUG=fatal-criticals`, this warning becomes a process abort. The root cause is an ownership mismatch between GStreamer's floating-reference model and the current Swift `Element` wrapper model:

- `gst_element_factory_make` and `gst_device_create_element` return elements with floating references.
- `gst_bin_add` sinks the floating reference when the element is added to a bin.
- The current Swift wrapper still behaves as if it owns an independent strong reference and unrefs in `deinit`.
- If the Swift wrapper drops before the parent pipeline drops, the wrapper can dispose an element that still has a parent, causing the critical.

This PRD tracks an internal ownership fix for `Element` only. The selected implementation is explicit `Element` transfer semantics plus a NULL-safe generic `GstObject` ref-sink shim. Public Swift APIs remain source-compatible.

## Status

Last updated: 2026-05-11.

- Drafting: complete.
- Implementation: complete.
- Functional requirements: all achieved (FR-1 through FR-14).
- Review: ready for maintainer review.
- Verification completed on 2026-05-11:
  - `swift build`
  - `swift test --filter ElementTests`
  - `swift test --filter DeviceMonitorTests`
  - `swift test`
- Verification notes:
  - Ownership tests use local `G_DEBUG=fatal-criticals` windows and passed without parent-disposal aborts.
  - The observed verification output contained no `still has a parent` critical lines.
  - During status verification, one full-suite run failed in unrelated `QueueLeakyBehaviorTests` downstream-leaky behavior; `swift test --filter QueueLeakyBehaviorTests` passed immediately after and the full suite passed on rerun.
- Related work:
  - `Sources/GStreamer/Element.swift` (`Element.TransferOwnership`, `Element.make`).
  - `Sources/GStreamer/Pipeline.swift` (`Pipeline.element(named:)`, `Pipeline.add(_:)` docs).
  - `Sources/GStreamer/DeviceMonitor.swift` (`Device.createElement(name:)`).
  - `Sources/CGStreamerShim/include/GStreamerShim.h` and `Sources/CGStreamerShim/GStreamerShim.c` (new shim).
  - `Tests/SwiftGStreamerTests/ElementTests.swift` (ownership regressions).

## Goals

- Remove parent-disposal critical logs caused by Swift wrappers dropping elements that are still parented by a pipeline.
- Make all `Element` wrapper construction sites declare whether the incoming `GstElement*` is floating, transfer-full, or borrowed.
- Preserve all public Swift API signatures and behavior other than fixing the ownership bug.
- Add ownership tests that automatically fail under local `G_DEBUG=fatal-criticals` if the critical returns.
- Document that `Element` wrappers keep their own strong reference and may be dropped after successful `Pipeline.add(_:)`.

## User Stories

### US-001: Define `Element` Transfer Semantics

**Description:** As a maintainer, I need `Element` initialization to encode GStreamer pointer transfer semantics so construction sites cannot silently choose the wrong ownership behavior.

**Acceptance Criteria:**
- [x] `Element` contains an internal nested `TransferOwnership` enum.
- [x] `.floating` calls a ref-sink operation so the wrapper owns a strong reference.
- [x] `.full` treats the incoming pointer as an already-owned transfer-full reference and does not add another reference.
- [x] `.none` is reserved for borrowed pointers and does not unref on wrapper deinit.
- [x] The enum is internal and does not change public Swift API.

### US-002: Dropping A Wrapper After `pipeline.add` Is Safe

**Description:** As a SwiftGStreamer user, I want `Element.make -> pipeline.add -> drop wrapper` to be safe so dynamic pipelines do not emit GStreamer parent-disposal criticals.

**Acceptance Criteria:**
- [x] `Element.make(factory:name:)` wraps factory-created elements with `.floating`.
- [x] `Device.createElement(name:)` wraps device-created elements with `.floating`.
- [x] Adding a factory-created element to a pipeline and letting the Swift wrapper go out of scope leaves the pipeline-owned element alive.
- [x] The ownership test runs under local `G_DEBUG=fatal-criticals` and does not abort.

### US-003: Cover Element Ownership Edge Paths

**Description:** As a maintainer, I need the non-happy ownership paths covered so future changes do not reintroduce leaks, use-after-free risks, or parent-disposal criticals.

**Acceptance Criteria:**
- [x] Add a test for `Element.make -> Pipeline.add(_:)` failure -> wrapper drop.
- [x] Add a test for `Element.make` -> never add to a bin -> wrapper drop.
- [x] Add a test for `Element.make -> Pipeline.add(_:) -> Pipeline.remove(_:) -> wrapper drop`.
- [x] Add a test for repeated `pipeline.element(named:)` calls returning independent Swift wrappers for the same underlying element.
- [x] Repeated `pipeline.element(named:)` wrappers can be dropped independently, and a later lookup still succeeds while the pipeline owns the element.

### US-004: Preserve Docs And Public Behavior

**Description:** As a library user, I need the fix to preserve existing call sites while making ownership behavior clear from API documentation.

**Acceptance Criteria:**
- [x] No public Swift symbols are added, removed, or renamed.
- [x] `Element.make(factory:name:)` documentation states the wrapper keeps its own strong reference and can be dropped after add.
- [x] `Pipeline.add(_:)` documentation states the wrapper keeps its own strong reference and can be dropped after successful add.
- [x] Existing examples remain valid.
- [x] `swift build`, focused ownership tests, `DeviceMonitorTests`, and full `swift test` pass.

## Functional Requirements

- [x] **FR-1:** Add `Element.TransferOwnership` as an internal nested enum with cases `.floating`, `.full`, and `.none`.
- [x] **FR-2:** Add a generic NULL-safe C shim: `GstObject* swift_gst_object_ref_sink(GstObject* object)`.
- [x] **FR-3:** The ref-sink shim must return `NULL` when passed `NULL`.
- [x] **FR-4:** The ref-sink shim must call `gst_object_ref_sink(object)` for non-NULL objects and return the resulting `GstObject*`.
- [x] **FR-5:** `Element.init(element:transfer:)` must call the ref-sink shim only for `.floating`.
- [x] **FR-6:** `Element.init(element:transfer:)` must unref on deinit for `.floating` and `.full`, and must not unref for `.none`.
- [x] **FR-7:** `Element.make(factory:name:)` must use `.floating`.
- [x] **FR-8:** `Device.createElement(name:)` must use `.floating`.
- [x] **FR-9:** `Pipeline.element(named:)` must use `.full` because `gst_bin_get_by_name` returns a transfer-full reference on success.
- [x] **FR-10:** `.none` is reserved for future borrowed-pointer wrappers; this PRD does not require a production call site that uses `.none`.
- [x] **FR-11:** Multiple `pipeline.element(named:)` calls for the same name must return independent Swift wrapper objects that share the same underlying `GstElement*`; each wrapper owns its own transfer-full reference.
- [x] **FR-12:** `Pipeline.add(_:)` keeps its `Bool` return type and does not become throwing.
- [x] **FR-13:** Ownership-related tests must use local fatal-critical detection only; this PRD must not enable `G_DEBUG=fatal-criticals` process-wide or CI-wide.
- [x] **FR-14:** Documentation for `Element.make(factory:name:)` and `Pipeline.add(_:)` must explicitly describe wrapper-owned strong references after creation/add.

## Non-Goals

- No Pad, Bus, Buffer, Sample, Caps, or VideoFrame ownership refactor.
- No public Swift API changes.
- No change from `Pipeline.add(_:) -> Bool` to a throwing API.
- No GStreamer minimum-version bump.
- No mutable state machine where an `Element` wrapper becomes invalid after being added to a pipeline.
- No broad fatal-critical policy for the full test process or CI workflow.
- No caching or identity guarantee for `pipeline.element(named:)` wrappers.

## Technical Considerations

- GStreamer transfer semantics are source-specific:
  - `gst_element_factory_make` returns a floating `GstElement*`.
  - `gst_device_create_element` returns a floating `GstElement*`.
  - `gst_bin_get_by_name` returns transfer-full; each successful call adds a reference for the caller.
- `gst_object_ref_sink` is safe for both floating and non-floating objects, but it increments the reference count for non-floating objects. Therefore `.full` must not call it.
- `pipeline.element(named:)` remains uncached. Calling it multiple times for the same name returns separate Swift wrapper objects that share the same underlying `GstElement*`; each wrapper owns the transfer-full reference from its own lookup.
- Tests should keep the fatal-critical window narrow and restore the previous `G_DEBUG` value after the ownership scenario finishes.
- The shim is intentionally generic over `GstObject*` rather than Element-specific so future ownership work can reuse the same primitive without changing this C API again.

## Test Plan

- Add ownership-focused tests in `Tests/SwiftGStreamerTests/ElementTests.swift`.
- Use local `G_DEBUG=fatal-criticals` only inside the ownership tests and restore any prior value afterward.
- Required verification commands:
  - `swift test --filter ElementTests`
  - `swift test --filter DeviceMonitorTests`
  - `swift test`
- During full-suite verification, check normal stderr for `still has a parent`; expected count is zero.

## Success Metrics

- `swift test --filter ElementTests` exits 0.
- `swift test --filter DeviceMonitorTests` exits 0.
- Full `swift test` exits 0.
- Ownership tests fail automatically on the old parent-disposal critical when `G_DEBUG=fatal-criticals` is active.
- Normal full-suite stderr contains zero `still has a parent` critical lines.

## Open Questions

- Should a future PRD extend the same explicit-transfer model to Pad, Bus, Buffer, Sample, or Caps wrappers after their individual transfer contracts are audited?
- Should a future test-only shim expose reference counts for tighter leak assertions, or should tests continue to rely on fatal-critical behavior and observable wrapper liveness?
- Should CI eventually run a separate fatal-critical test job after all existing GLib/GStreamer criticals have been eliminated?

## References

- [`gst_element_factory_make`](https://gstreamer.freedesktop.org/documentation/gstreamer/gstelementfactory.html)
- [`gst_bin_get_by_name`](https://gstreamer.freedesktop.org/documentation/gstreamer/gstbin.html)
- [`gst_device_create_element`](https://gstreamer.freedesktop.org/documentation/gstreamer/gstdevice.html)
- [`g_object_ref_sink`](https://docs.gtk.org/gobject/method.Object.ref_sink.html)
