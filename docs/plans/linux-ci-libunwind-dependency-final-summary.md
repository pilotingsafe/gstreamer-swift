# Linux CI libunwind Dependency Final Summary

## Final Status

Complete for the Linux CI apt dependency fix.

## Approved Plan

- `docs/plans/linux-ci-libunwind-dependency-plan.md`
- Plan review round 1: `Verdict: No Findings`
- Revised plan review after aligning Swift-version wording with current branch
  state: `Verdict: No Findings`

## BDD Specs

- `docs/bdd/linux-ci-libunwind-dependency.feature`

## BDD Empty-Test Checkpoint

- Empty skeleton: `Tests/SwiftGStreamerTests/LinuxCIUbuntuDependencyBDDTests.swift`
- Checkpoint status: created and verified before formal tests.
- Verification command:
  `rg -n "#expect|#require|try Self|let |var |return|=|\\.contents|FileManager|apt|get" Tests/SwiftGStreamerTests/LinuxCIUbuntuDependencyBDDTests.swift`
- Verification result: no matches before formal tests were added.

## Implementation Summary

- Added static Swift Testing coverage for the Ubuntu CI dependency install step.
- Updated the Ubuntu CI dependency install step to remove versioned
  `libunwind-13-dev` and `libunwind-14-dev` packages after `apt-get update`.
- Added explicit `libunwind-dev` installation before `libgstreamer1.0-dev`.
- Preserved the existing Ubuntu GStreamer packages and macOS Homebrew
  dependency setup.

## Test Summary

- `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`
  passed.
- `swiftly run swift --version` passed with local Apple Swift 6.3.1.
- `swiftly run which swift` passed.
- Red phase: `swiftly run swift test --filter LinuxCIUbuntuDependencyBDDTests`
  failed before the workflow patch because the Ubuntu step did not remove
  versioned libunwind dev packages and did not install `libunwind-dev`.
- Green phase: `swiftly run swift test --filter LinuxCIUbuntuDependencyBDDTests`
  passed with 3 tests in 1 suite.
- `git diff --check` passed.

## Review Summary

- Spec compliance: No Findings.
- Code quality: No Findings.

## Remaining Notes

- The final proof for the apt resolver behavior is the next GitHub Actions
  Ubuntu 22.04 run.
- The repository now intentionally validates `SWIFT_VERSION: 6.3.1`; that
  baseline change is handled by the Swift toolchain migration work, while this
  summary remains scoped to the Linux apt fix.
