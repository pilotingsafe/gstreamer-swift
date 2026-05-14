# Linux CI libunwind Dependency Plan

> Toolchain baseline note: the repository support baseline is now Swift 6.3.1.
> This Linux apt dependency plan remains active, with Swift-version wording
> aligned to the current baseline.

## Summary

Fix the Ubuntu 22.04 CI setup failure where installing `libgstreamer1.0-dev`
stops with an unmet `libunwind-dev` dependency before Swift, build, or tests
run.

## Problem

The Linux CI job installs Swift support packages and GStreamer packages in one
early apt transaction. On the GitHub-hosted Ubuntu 22.04 runner, that transaction
fails while resolving `libgstreamer1.0-dev` because it depends on
`libunwind-dev`. Ubuntu Jammy has a known conflict between versioned LLVM
`libunwind-13-dev` / `libunwind-14-dev` packages and the unversioned
`libunwind-dev` package required by GStreamer development headers.

## Goals

- Allow the Ubuntu 22.04 CI job to complete the apt dependency install step.
- Keep GStreamer development packages installed through Ubuntu packages.
- Preserve the existing CI Swift toolchain selection.
- Keep macOS CI behavior unchanged.
- Add deterministic repository tests that guard the workflow dependency order
  and conflict handling.

## Non-Goals

- Do not change Swift package public API.
- Do not change the package platform or Swift tools-version requirements.
- Do not replace Ubuntu package installs with source builds, PPAs, containers,
  or cached binary artifacts.
- Do not address the separate macOS Swift frontend crash in this change.

## Current Behavior

The Ubuntu job runs:

1. `sudo apt-get update`
2. `sudo apt-get install -y` with Swift support packages and GStreamer packages
3. `libgstreamer1.0-dev` dependency resolution fails on `libunwind-dev`
4. The job exits with code 100 before `swiftly`, preflight, build, or test steps

## Proposed Behavior

The Ubuntu dependency setup should:

1. Run `apt-get update`.
2. Remove versioned LLVM `libunwind-13-dev` and `libunwind-14-dev` packages if
   present on the hosted image.
3. Install unversioned `libunwind-dev` explicitly in the same apt package list
   as `libgstreamer1.0-dev`.
4. Continue to install the existing Swift support and GStreamer runtime/plugin
   packages.
5. Leave macOS dependency installation unchanged.

## Affected Modules

- `.github/workflows/ci.yml`
- `Tests/SwiftGStreamerTests/LinuxCIUbuntuDependencyBDDTests.swift`
- `docs/bdd/linux-ci-libunwind-dependency.feature`
- `docs/plans/linux-ci-libunwind-dependency-*`

## Public API and Data Changes

None.

## Compatibility

The change is scoped to the GitHub Actions Ubuntu 22.04 runner. It preserves
the workflow's existing Swift toolchain selection, existing GStreamer package
names, and macOS behavior.

## Safety and Rollout

Removing versioned LLVM libunwind development packages is limited to the
ephemeral CI runner and only happens before installing the unversioned
development package that GStreamer requires. Runtime GStreamer packages and
Swift package source are unchanged.

## BDD Scenario Mapping

- Scenario: Ubuntu dependency setup resolves the GStreamer libunwind dependency.
  - Formal test: workflow must remove conflicting versioned libunwind dev
    packages before installing `libgstreamer1.0-dev`.
  - Formal test: workflow must explicitly install `libunwind-dev` before
    `libgstreamer1.0-dev`.
- Scenario: Ubuntu setup keeps existing Swift and GStreamer dependencies.
  - Formal test: workflow keeps `libcurl4-openssl-dev`, `pkg-config`,
    `python3-lldb-13`, GStreamer development packages, tools, and plugins.
- Scenario: macOS setup is unaffected.
  - Formal test: workflow keeps the macOS Homebrew step and does not add
    libunwind conflict handling to it.

## Empty-Test Skeleton Plan

Create `Tests/SwiftGStreamerTests/LinuxCIUbuntuDependencyBDDTests.swift` with an
empty Swift Testing suite containing Given/When/Then comments and empty test
functions for the three BDD scenarios. Verify the skeleton contains no
assertions, setup logic, helpers, or executable bodies before adding formal
tests.

## Formal Test Strategy

Use Swift Testing static workflow tests because the failure is in CI YAML
dependency ordering and cannot be reproduced reliably on the local macOS
machine. The tests should parse `.github/workflows/ci.yml` as text and assert:

- the Ubuntu install step removes `libunwind-13-dev` and `libunwind-14-dev`
  after `apt-get update` and before `apt-get install`;
- the apt install package list includes `libunwind-dev` before
  `libgstreamer1.0-dev`;
- existing Swift support and GStreamer packages remain present;
- the macOS Homebrew dependency step remains limited to `pkgconf gstreamer`.

## Implementation Sequence

1. Add plan and Gherkin BDD artifacts.
2. Obtain plan review with `Verdict: No Findings`.
3. Add and verify the empty Swift Testing skeleton.
4. Replace the empty skeleton with formal static workflow tests.
5. Run the targeted test and observe failure before the workflow fix when
   feasible.
6. Patch `.github/workflows/ci.yml` with versioned libunwind removal and
   explicit `libunwind-dev`.
7. Rerun focused tests.
8. Run spec compliance review, code-quality review, and final audit.

## Risks

- Local macOS testing can verify workflow structure but cannot prove apt
  resolution on the hosted Ubuntu image. The final confirmation is the GitHub
  Actions Ubuntu job.
- Removing versioned libunwind development packages could affect unrelated
  tools on the hosted image, but the CI job does not build against those
  versioned development headers.

## Acceptance Criteria

- Static workflow tests pass.
- `.github/workflows/ci.yml` removes versioned libunwind development packages
  before the Ubuntu apt install transaction.
- `.github/workflows/ci.yml` explicitly installs `libunwind-dev` before
  `libgstreamer1.0-dev`.
- Existing Ubuntu Swift support and GStreamer packages remain in the install
  list.
- macOS dependency setup remains unchanged.
- The next Ubuntu CI run reaches the Swift/GStreamer preflight or later instead
  of failing at `libgstreamer1.0-dev : Depends: libunwind-dev`.

## Assumptions

- The failing CI run uses GitHub-hosted Ubuntu 22.04 with the package conflict
  visible in the current runner image.
- `libunwind-13-dev` and `libunwind-14-dev` package names are resolvable on
  Ubuntu 22.04 even when they are not installed.
