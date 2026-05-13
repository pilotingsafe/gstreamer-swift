Feature: Swift 6.2 compatible VideoFrame byte-count smoke tests

  Background:
    Given the package supports Swift 6.2
    And CI validates the package with Swift 6.2.4 on macOS
    And VideoFrame exposes read-only bytes through both bytes and withUnsafeBytes

  Scenario: AppSink smoke tests validate frame byte counts without lifetime-bound macro access
    Given an AppSink smoke test awaits a VideoFrame from a video pipeline
    When the test validates the frame byte count
    Then the test computes the byte count outside the Swift Testing macro
    And the test asserts on a plain local byte-count value

  Scenario: AppSource roundtrip tests validate frame byte counts without lifetime-bound macro access
    Given an AppSource/AppSink roundtrip test awaits a VideoFrame
    When the test validates the roundtripped frame byte count
    Then the test computes the byte count outside the Swift Testing macro
    And the test asserts on a plain local byte-count value

  Scenario: Read-only API tests preserve coverage for both VideoFrame byte APIs
    Given a read-only VideoFrame API test awaits a BGRA frame
    When the test validates read-only byte access
    Then the test reads bytes.byteCount into a local value before asserting
    And the test separately validates the withUnsafeBytes byte count

  Scenario: Static safety guards accept equivalent byte-count evidence
    Given a static safety test guards async media smoke test evidence
    When the AppSink byte-count assertion is reshaped for Swift 6.2 compatibility
    Then the guard accepts post-loop byte-count validation through withUnsafeBytes
    And the guard does not require the old direct bytes.byteCount macro snippet

  Scenario: CI continues to validate Swift 6.2 compatibility
    Given macOS CI intentionally validates Swift 6.2 compatibility
    When the compiler crash workaround is implemented
    Then the CI workflow keeps Swift 6.2.4 as the selected Swift version
    And no public VideoFrame API is changed to avoid the crash
