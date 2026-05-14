Feature: CI end-to-end GStreamer example tests

  Scenario: CI pulls finite synthetic video frames from an app sink
    Given the CI runner has the package's GStreamer runtime dependencies
    And a finite synthetic BGRA video source is connected to an app sink
    When the Swift test runs the pipeline and reads frames from the app sink
    Then three video frames are delivered to Swift
    And each delivered frame has the expected BGRA byte size
    And the delivered stream exposes the expected video dimensions and format
    And the finite pipeline reaches end-of-stream without a bus error

  Scenario: CI pushes deterministic Swift video frames into a GStreamer sink
    Given the CI runner has the package's GStreamer runtime dependencies
    And a Swift app source is connected to a non-rendering GStreamer sink
    When the Swift test pushes deterministic BGRA frames and ends the stream
    Then the GStreamer pipeline observes each pushed frame downstream
    And the pipeline reaches end-of-stream without a bus error
