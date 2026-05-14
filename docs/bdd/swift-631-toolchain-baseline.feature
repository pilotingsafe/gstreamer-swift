Feature: Swift 6.3.1 toolchain baseline

  Background:
    Given the package minimum is Swift 6.3.1
    And CI validates the package with Swift 6.3.1 on Linux and macOS
    And VideoFrame exposes read-only bytes through both bytes and withUnsafeBytes

  Scenario: Package manifest declares the Swift 6.3.1 minimum
    Given the package has a SwiftPM manifest
    When the toolchain baseline is raised
    Then Package.swift declares Swift 6.3.1 as the minimum tools version

  Scenario: CI validates Swift 6.3.1
    Given the GitHub Actions workflow installs Swift through swiftly
    When CI verifies the selected Swift version
    Then the workflow selects Swift 6.3.1

  Scenario: Documentation states the Swift 6.3.1 baseline
    Given users read the README
    When they check the supported Swift version
    Then the README states the Swift 6.3.1 baseline

  Scenario: VideoFrame byte APIs remain public
    Given the toolchain baseline change does not alter public GStreamer APIs
    When the source is checked for VideoFrame byte access
    Then VideoFrame.bytes remains public
    And VideoFrame.withUnsafeBytes remains public
