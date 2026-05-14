Feature: Linux CI resolves GStreamer libunwind dependencies

  Scenario: Ubuntu dependency setup resolves the GStreamer libunwind dependency
    Given the Ubuntu 22.04 CI runner may have versioned LLVM libunwind development packages installed
    And GStreamer development headers require the unversioned libunwind development package
    When Linux CI installs Swift support and GStreamer dependencies
    Then the workflow removes conflicting versioned libunwind development packages first
    And the workflow installs the unversioned libunwind development package before GStreamer development headers

  Scenario: Ubuntu setup keeps existing Swift and GStreamer dependencies
    Given the package still needs Swift support libraries and GStreamer runtime plugins on Ubuntu
    When Linux CI installs dependencies
    Then the workflow keeps the existing Swift support packages
    And the workflow keeps the existing GStreamer development, tool, and plugin packages

  Scenario: macOS dependency setup is unaffected
    Given macOS CI installs GStreamer through Homebrew
    When the Linux libunwind dependency fix is applied
    Then the macOS dependency step still installs only the existing Homebrew packages
    And macOS CI does not run Ubuntu libunwind conflict handling
