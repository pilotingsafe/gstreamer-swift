import Testing

@testable import GStreamer

@Suite("Device Monitor Tests")
struct DeviceMonitorTests {

  init() throws {
    try GStreamer.initialize()
  }

  @Test("Create DeviceMonitor")
  func createMonitor() {
    let monitor = DeviceMonitor()
    _ = monitor  // Just verify creation doesn't crash
  }

  @Test("List video sources")
  func listVideoSources() {
    let monitor = DeviceMonitor()
    let cameras = monitor.videoSources()

    // Host hardware is optional; when devices exist, their reported fields must be usable.
    for camera in cameras {
      assertDeviceHasValidFields(camera)
      #expect(camera.deviceClass.contains("Video"))
      #expect(camera.deviceClass.contains("Source"))
    }
  }

  @Test("List audio sources")
  func listAudioSources() {
    let monitor = DeviceMonitor()
    let mics = monitor.audioSources()

    for mic in mics {
      assertDeviceHasValidFields(mic)
      #expect(mic.deviceClass.contains("Audio"))
      #expect(mic.deviceClass.contains("Source"))
    }
  }

  @Test("List audio sinks")
  func listAudioSinks() {
    let monitor = DeviceMonitor()
    let speakers = monitor.audioSinks()

    for speaker in speakers {
      assertDeviceHasValidFields(speaker)
      #expect(speaker.deviceClass.contains("Audio"))
      #expect(speaker.deviceClass.contains("Sink"))
    }
  }

  @Test("List all devices")
  func listAllDevices() {
    let monitor = DeviceMonitor()
    let devices = monitor.allDevices()

    for device in devices {
      assertDeviceHasValidFields(device)
    }
  }

  @Test("Device has caps")
  func deviceHasCaps() {
    let monitor = DeviceMonitor()
    let devices = monitor.allDevices()

    for device in devices {
      if let caps = device.caps {
        #expect(!caps.isEmpty)
      }
    }
  }

  @Test("Create element from device")
  func createElementFromDevice() {
    let monitor = DeviceMonitor()
    let devices = monitor.videoSources()

    // Hardware is optional, and a discovered device may still fail element creation.
    if let camera = devices.first {
      let element = camera.createElement(name: "test_camera")
      if let el = element {
        #expect(!el.name.isEmpty)
      }
    }
  }

  private func assertDeviceHasValidFields(_ device: Device) {
    #expect(!device.displayName.isEmpty)
    #expect(!device.deviceClass.isEmpty)
  }
}
