import CGStreamer
import CGStreamerApp
import CGStreamerShim

extension MediaStreamBackpressure {
  internal static let encodedPacketsNewest = 8
}

/// High-level microphone capture API with automatic source selection and encoding.
///
/// AudioSource provides a fluent builder for common microphone pipelines,
/// including sample rate, channel count, format, and optional encoding.
///
/// ## Example
///
/// ```swift
/// let mic = try AudioSource.microphone()
///     .withSampleRate(48_000)
///     .withChannels(2)
///     .withFormat(.s16le)
///     .withOpusEncoding(bitrate: 128_000)
///     .build()
///
/// for await packet in mic.packets() {
///     // Process encoded audio packets
/// }
/// ```
public final class AudioSource: @unchecked Sendable {
  /// Output encoding for audio capture.
  public enum Encoding: Sendable, Hashable {
    case raw
    case opus(bitrate: Int)
    case aac(bitrate: Int)
  }

  /// Errors that can occur when building an audio source.
  public enum AudioSourceError: Error, Sendable, CustomStringConvertible {
    case deviceNotFound(String)
    case devicePathUnsupported(String)
    case invalidConfiguration(String)
    case noWorkingPipeline([String])

    public var description: String {
      switch self {
      case .deviceNotFound(let name):
        return "No microphone found matching: \(name)"
      case .devicePathUnsupported(let path):
        return "Device path not supported on this platform: \(path)"
      case .invalidConfiguration(let message):
        return "Invalid AudioSource configuration: \(message)"
      case .noWorkingPipeline(let diagnostics):
        if diagnostics.isEmpty {
          return "No working audio pipeline found"
        }
        return "No working audio pipeline found. Attempts:\n" + diagnostics.joined(separator: "\n")
      }
    }
  }

  internal let pipeline: Pipeline
  private let audioSink: AudioBufferSink?
  private let packetSink: AudioPacketSink?
  private let pipelineDescription: String
  private let buildDiagnostics: [String]
  internal let reliableCoordinator: LiveAudioReliablePacketCoordinator?
  internal let shutdownCoordinator = AudioSourceShutdownCoordinator()

  /// The encoding configured for this source.
  public let encoding: Encoding

  fileprivate init(
    pipeline: Pipeline,
    audioSink: AudioBufferSink?,
    packetSink: AudioPacketSink?,
    reliableCoordinator: LiveAudioReliablePacketCoordinator?,
    pipelineDescription: String,
    diagnostics: [String],
    encoding: Encoding
  ) {
    self.pipeline = pipeline
    self.audioSink = audioSink
    self.packetSink = packetSink
    self.reliableCoordinator = reliableCoordinator
    self.pipelineDescription = pipelineDescription
    self.buildDiagnostics = diagnostics
    self.encoding = encoding
  }

  deinit {
    reliableCoordinator?.stopFromSource()
    pipeline.stop()
  }

  /// The selected pipeline description used to build this source.
  public var selectedPipeline: String {
    pipelineDescription
  }

  /// Diagnostics from pipeline selection and fallback attempts.
  public var diagnostics: [String] {
    buildDiagnostics
  }

  /// An async stream of raw audio buffers.
  ///
  /// - Note: Only available when encoding is ``AudioSource/Encoding/raw``.
  ///   For encoded output, use ``packets()``.
  public func buffers() -> AsyncStream<AudioBuffer> {
    guard let audioSink else {
      return AsyncStream { $0.finish() }
    }
    return audioSink.buffers()
  }

  /// An async stream of encoded audio packets.
  ///
  /// Encoded packet streams are realtime best-effort streams. They keep a
  /// bounded queue of recent packets and may drop older packets under
  /// slow-consumer backpressure. For raw capture, this returns an empty stream;
  /// prefer ``buffers()``. For sources built with reliable delivery, this
  /// returns an empty stream so the reliable bridge remains the only consumer
  /// of the live appsink.
  public func packets() -> AsyncStream<Buffer> {
    guard let packetSink else {
      return AsyncStream { $0.finish() }
    }
    return packetSink.packets()
  }

  /// Return encoded live reliable packets for a source built with reliable delivery.
  ///
  /// Reliable live delivery is available only for encoded audio sources built
  /// with ``AudioSourceBuilder/withReliableDelivery(leaky:maxBuffers:maxBytes:maxTime:)``.
  /// Raw live audio should continue to use ``buffers()``; realtime monitoring
  /// should continue to use ``packets()``.
  ///
  /// The returned sequence owns the one live appsink reliable bridge for this
  /// `AudioSource`. A source supports only one reliable sequence.
  ///
  /// - Throws: ``GStreamerError/invalidArgument(parameter:reason:)`` if reliable
  ///   delivery was not configured or the reliable appsink is already owned.
  public func reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>> {
    guard let reliableCoordinator else {
      throw GStreamerError.invalidArgument(
        parameter: "AudioSource.reliablePackets",
        reason: "Reliable delivery is not configured; call withReliableDelivery(...) before build()."
      )
    }
    return try reliableCoordinator.reliablePackets()
  }

  /// Stop the underlying pipeline immediately.
  ///
  /// This is the realtime shutdown path. It does not send EOS and does not
  /// guarantee delivery of encoder tail packets. Reliable live callers that
  /// need an EOS drain should use ``finalize(timeout:)``.
  public func stop() async {
    shutdownCoordinator.stop(
      pipeline: pipeline,
      reliableCoordinator: reliableCoordinator
    )
  }

  /// Gracefully finalize a live reliable source.
  ///
  /// `finalize(timeout:)` sends EOS, waits for Bus EOS or ERROR, then waits
  /// for the active reliable iterator to drain to `nil` or be cancelled before
  /// stopping the pipeline. Calling it more than once is safe. Calling
  /// ``stop()`` first keeps the immediate-stop behavior and does not restart
  /// the pipeline.
  ///
  /// - Parameter timeout: Maximum time to wait for Bus EOS or ERROR.
  /// - Throws: ``GStreamerError/busError(_:source:debug:)`` on EOS send
  ///   failure, bus error, or timeout.
  public func finalize(timeout: Duration = .seconds(5)) async throws {
    try await shutdownCoordinator.finalize(
      pipeline: pipeline,
      reliableCoordinator: reliableCoordinator,
      timeout: timeout
    )
  }

  internal func reliablePacketRuntimeSnapshotForTesting()
    -> ReliablePacketRuntimeSnapshotForTesting
  {
    let shutdownState = shutdownCoordinator.snapshot()
    return reliableCoordinator?.runtimeSnapshot(
      shutdownState: shutdownState
    ) ?? ReliablePacketRuntimeSnapshotForTesting(
      newSampleHandlerCount: 0,
      pendingContinuationCount: 0,
      cleanupAcknowledgementCount: 0,
      finalized: shutdownState.finalized,
      stopped: shutdownState.stopped,
      activePipeline: nil,
      activeSequence: false
    )
  }

  internal func reliablePacketPipelineForTesting() -> Pipeline? {
    reliableCoordinator?.activePipelineForTesting()
  }

  internal func reliableFirstSampleCapsForTesting() async throws -> String {
    guard let reliableCoordinator else {
      throw GStreamerError.invalidArgument(
        parameter: "AudioSource.reliablePackets",
        reason: "Reliable delivery is not configured; call withReliableDelivery(...) before build()."
      )
    }
    return try await reliableCoordinator.firstSampleCapsForTesting()
  }

  internal func injectReliablePacketBusErrorForTesting(
    message: String,
    source: String? = "AudioSource.reliablePackets",
    debug: String? = nil
  ) {
    reliableCoordinator?.injectBusErrorForTesting(
      GStreamerError.busError(message, source: source, debug: debug)
    )
  }

  internal func injectReliableDiscontinuityForTesting(
    kind: Discontinuity.Kind,
    pts: UInt64? = nil,
    duration: UInt64? = nil
  ) {
    reliableCoordinator?.injectDiscontinuityForTesting(
      kind: kind,
      pts: pts,
      duration: duration
    )
  }

  internal func injectReliableFinalizeBusErrorForTesting(
    message: String,
    source: String? = "AudioSource.finalize",
    debug: String? = nil
  ) {
    shutdownCoordinator.injectFinalizeBusErrorForTesting(
      GStreamerError.busError(message, source: source, debug: debug)
    )
  }

  /// Discover available microphones on the system.
  public static func availableMicrophones() throws -> [AudioDeviceInfo] {
    let monitor = DeviceMonitor()
    let devices = monitor.audioSources()

    return devices.enumerated().map { index, device in
      let uniqueID = AudioSource.uniqueID(for: device, index: index)
      let capabilities = AudioSource.parseCapabilities(device.caps)
      return AudioDeviceInfo(
        index: index,
        name: device.displayName,
        uniqueID: uniqueID,
        type: .input,
        capabilities: capabilities
      )
    }
  }

  /// Create a microphone source using the default device (typically index 0).
  public static func microphone(deviceIndex: Int = 0) -> AudioSourceBuilder {
    AudioSourceBuilder(selection: .deviceIndex(deviceIndex))
  }

  /// Create a microphone source by matching a device display name.
  public static func microphone(name: String) throws -> AudioSourceBuilder {
    let resolved = try resolveDeviceSelection(forName: name)
    return AudioSourceBuilder(selection: resolved)
  }

  /// Create a microphone source using a platform-specific device path.
  ///
  /// - Note: Currently supported on Linux.
  public static func microphone(devicePath: String) throws -> AudioSourceBuilder {
    #if os(Linux)
      return AudioSourceBuilder(selection: .devicePath(devicePath))
    #else
      throw AudioSourceError.devicePathUnsupported(devicePath)
    #endif
  }

  /// Convenience initializer for common cases.
  public static func microphone(
    sampleRate: Int,
    channels: Int,
    format: AudioFormat = .s16le,
    encoding: Encoding = .raw
  ) throws -> AudioSource {
    try microphone()
      .withSampleRate(sampleRate)
      .withChannels(channels)
      .withFormat(format)
      .withEncoding(encoding)
      .build()
  }

  private static func resolveDeviceSelection(forName name: String) throws
    -> AudioSourceBuilder.DeviceSelection
  {
    let monitor = DeviceMonitor()
    let devices = monitor.audioSources()
    let normalized = name.lowercased()

    for (index, device) in devices.enumerated() {
      if device.displayName.lowercased() == normalized {
        #if os(Linux)
          if let path = device.property("device.path")
            ?? device.property("api.alsa.path")
            ?? device.property("api.pulse.path")
            ?? device.property("api.pipewire.path")
          {
            return .devicePath(path)
          }
          return .deviceIndex(index)
        #else
          return .deviceIndex(index)
        #endif
      }
    }

    throw AudioSourceError.deviceNotFound(name)
  }

  private static func uniqueID(for device: Device, index: Int) -> String {
    if let path = device.property("device.path") {
      return path
    }
    if let path = device.property("api.alsa.path") {
      return path
    }
    if let path = device.property("api.pulse.path") {
      return path
    }
    if let path = device.property("api.pipewire.path") {
      return path
    }
    if let serial = device.property("device.serial") {
      return serial
    }
    if let uuid = device.property("device.uuid") {
      return uuid
    }
    return "device-\(index)"
  }

  private static func parseCapabilities(_ caps: String?) -> AudioDeviceInfo.Capabilities {
    guard let caps else {
      return AudioDeviceInfo.Capabilities(sampleRates: [], channels: [], formats: [])
    }

    let structures = caps.split(separator: ";")
    var sampleRates: [Int] = []
    var channels: [Int] = []
    var formats: [AudioFormat] = []

    for structure in structures {
      let components = structure.split(separator: ",")
      for component in components {
        let trimmed = component.trimmingWhitespace()
        guard let separator = trimmed.firstIndex(of: "=") else { continue }
        let key = trimmed[..<separator].trimmingWhitespace()
        let value = trimmed[trimmed.index(after: separator)...].trimmingWhitespace()
        let cleaned = stripTypeAnnotation(String(value))

        if key == "rate" {
          sampleRates.append(contentsOf: parseIntList(from: cleaned))
        } else if key == "channels" {
          channels.append(contentsOf: parseIntList(from: cleaned))
        } else if key == "format" {
          formats.append(contentsOf: parseAudioFormats(from: cleaned))
        }
      }
    }

    let uniqueRates = Array(Set(sampleRates)).sorted()
    let uniqueChannels = Array(Set(channels)).sorted()
    let uniqueFormats = Array(Set(formats))
      .sorted { $0.formatString < $1.formatString }

    return AudioDeviceInfo.Capabilities(
      sampleRates: uniqueRates,
      channels: uniqueChannels,
      formats: uniqueFormats
    )
  }
}

/// Builder for configuring an AudioSource pipeline.
public struct AudioSourceBuilder: Sendable {
  fileprivate enum DeviceSelection: Sendable {
    case deviceIndex(Int)
    case devicePath(String)
  }

  private let selection: DeviceSelection
  private var sampleRate: Int?
  private var channels: Int?
  private var format: AudioFormat?
  private var encoding: AudioSource.Encoding = .raw
  private var reliableDeliveryRequest: AudioSourceReliableDeliveryRequest?
  private var reliableDeliveryHooks = AudioSourceReliableDeliveryHooks()
  private var sourcePipelineCandidatesForTesting: [String]?

  fileprivate init(selection: DeviceSelection) {
    self.selection = selection
  }

  /// Set the sample rate in Hz.
  public func withSampleRate(_ rate: Int) -> AudioSourceBuilder {
    var copy = self
    copy.sampleRate = rate
    return copy
  }

  /// Set the number of channels.
  public func withChannels(_ channels: Int) -> AudioSourceBuilder {
    var copy = self
    copy.channels = channels
    return copy
  }

  /// Set the sample format.
  public func withFormat(_ format: AudioFormat) -> AudioSourceBuilder {
    var copy = self
    copy.format = format
    return copy
  }

  /// Set output encoding.
  public func withEncoding(_ encoding: AudioSource.Encoding) -> AudioSourceBuilder {
    var copy = self
    copy.encoding = encoding
    return copy
  }

  /// Encode audio to Opus.
  public func withOpusEncoding(bitrate: Int) -> AudioSourceBuilder {
    withEncoding(.opus(bitrate: bitrate))
  }

  /// Encode audio to AAC.
  public func withAACEncoding(bitrate: Int) -> AudioSourceBuilder {
    withEncoding(.aac(bitrate: bitrate))
  }

  /// Opt into encoded live reliable delivery with an explicit GStreamer queue policy.
  ///
  /// Reliable live delivery inserts a bounded `queue` before the encoder and
  /// uses a bounded non-dropping appsink. `QueueLeaky.none` blocks upstream
  /// when the queue is full, which avoids silent queue drops when consumers
  /// keep up but can surface source xruns or device-level loss under sustained
  /// slowness. `QueueLeaky.upstream` drops incoming buffers when full, keeping
  /// older queued data. `QueueLeaky.downstream` drops older queued buffers to
  /// keep latency lower.
  ///
  /// Reliable live delivery is encoded-audio-only in this phase; configure
  /// Opus or AAC before calling ``build()``. Raw reliable live buffers,
  /// VideoSource reliable delivery, fan-out, and recording conveniences are
  /// future work.
  public func withReliableDelivery(
    leaky: QueueLeaky = .none,
    maxBuffers: UInt? = 256,
    maxBytes: UInt? = nil,
    maxTime: Duration? = .seconds(2)
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryRequest = AudioSourceReliableDeliveryRequest(
      leaky: leaky,
      maxBuffers: maxBuffers,
      maxBytes: maxBytes,
      maxTime: maxTime
    )
    return copy
  }

  internal func withReliableDeliveryCandidateDescriptionsForTesting(
    _ descriptions: [String],
    sinkName: String,
    queueName: String? = nil
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.candidateDescriptionsForTesting = descriptions
    copy.reliableDeliveryHooks.candidateSinkNameForTesting = sinkName
    copy.reliableDeliveryHooks.candidateQueueNameForTesting = queueName
    return copy
  }

  internal func withReliablePacketCandidateDescriptionsForTesting(
    _ descriptions: [String],
    sinkName: String,
    queueName: String? = nil
  ) -> AudioSourceBuilder {
    withReliableDeliveryCandidateDescriptionsForTesting(
      descriptions,
      sinkName: sinkName,
      queueName: queueName
    )
  }

  internal func withReliableDeliveryOnCandidateStartForTesting(
    _ callback: @escaping @Sendable (Pipeline, String) -> Void
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.onCandidateStartForTesting = callback
    return copy
  }

  internal func withReliablePacketOnCandidateStartForTesting(
    _ callback: @escaping @Sendable (Pipeline, String) -> Void
  ) -> AudioSourceBuilder {
    withReliableDeliveryOnCandidateStartForTesting(callback)
  }

  internal func withReliableDeliveryOnCleanupForTesting(
    _ callback: @escaping @Sendable () -> Void
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.onCleanupForTesting = callback
    return copy
  }

  internal func withReliablePacketOnCleanupForTesting(
    _ callback: @escaping @Sendable () -> Void
  ) -> AudioSourceBuilder {
    withReliableDeliveryOnCleanupForTesting(callback)
  }

  internal func _withReliableDeliveryFirstSampleCapsProbe(
    _ probe: (@Sendable (String) -> Void)?
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.firstSampleCapsProbe = probe
    return copy
  }

  internal func _withFirstSampleCapsProbe(
    _ probe: (@Sendable (String) -> Void)?
  ) -> AudioSourceBuilder {
    _withReliableDeliveryFirstSampleCapsProbe(probe)
  }

  internal func withReliableDeliverySendEOSForTesting(
    _ sendEOS: @escaping @Sendable (Pipeline) -> Bool
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.sendEOSForTesting = sendEOS
    return copy
  }

  internal func withReliablePacketSendEOSForTesting(
    _ sendEOS: @escaping @Sendable (Pipeline) -> Bool
  ) -> AudioSourceBuilder {
    withReliableDeliverySendEOSForTesting(sendEOS)
  }

  internal func withReliableDeliveryFinalizeErrorForTesting(
    _ error: (@Sendable () -> GStreamerError?)?
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.finalizeErrorAfterSendEOSForTesting = error
    return copy
  }

  internal func withReliableDeliverySuppressEOSCallbacksForTesting(
    _ enabled: Bool = true
  ) -> AudioSourceBuilder {
    var copy = self
    copy.reliableDeliveryHooks.suppressEOSCallbacksForTesting = enabled
    return copy
  }

  internal func withReliablePacketSuppressEOSCallbacksForTesting(
    _ enabled: Bool = true
  ) -> AudioSourceBuilder {
    withReliableDeliverySuppressEOSCallbacksForTesting(enabled)
  }

  internal func _withSourcePipelineCandidatesForTesting(_ candidates: [String])
    -> AudioSourceBuilder
  {
    var copy = self
    copy.sourcePipelineCandidatesForTesting = candidates
    return copy
  }

  internal func _pipelineDescriptionForTesting(
    source: String,
    sinkName: String,
    queueName: String
  ) throws -> String {
    let reliableDelivery = try makeReliableDeliveryConfiguration(allowUnboundedForTesting: true)
    return buildPipelineDescription(
      source: source,
      encoder: resolveEncoderCandidates().first ?? nil,
      sinkName: sinkName,
      queueName: queueName,
      reliableDelivery: reliableDelivery
    )
  }

  /// Build the AudioSource, selecting the first working pipeline.
  public func build() throws -> AudioSource {
    if let sampleRate, sampleRate <= 0 {
      throw AudioSource.AudioSourceError.invalidConfiguration("Sample rate must be positive")
    }

    if let channels, channels <= 0 {
      throw AudioSource.AudioSourceError.invalidConfiguration("Channels must be positive")
    }

    if case .opus(let bitrate) = encoding, bitrate <= 0 {
      throw AudioSource.AudioSourceError.invalidConfiguration("Opus bitrate must be positive")
    }

    if case .aac(let bitrate) = encoding, bitrate <= 0 {
      throw AudioSource.AudioSourceError.invalidConfiguration("AAC bitrate must be positive")
    }

    let reliableDelivery = try makeReliableDeliveryConfiguration()

    let sinkName = reliableDeliveryHooks.candidateSinkNameForTesting
      ?? "sink\(UInt32.random(in: 0...UInt32.max))"
    let queueName = reliableDeliveryHooks.candidateQueueNameForTesting
      ?? "reliableQueue\(UInt32.random(in: 0...UInt32.max))"

    let sourceCandidates = sourcePipelineCandidatesForTesting ?? resolveSourceCandidates()
    let encoderCandidates = resolveEncoderCandidates()
    let explicitDescriptions = reliableDelivery?.candidateDescriptionsForTesting

    var diagnostics: [String] = []

    let descriptions: [String]
    if let explicitDescriptions {
      descriptions = explicitDescriptions
    } else {
      descriptions = sourceCandidates.flatMap { source in
        encoderCandidates.map { encoder in
          buildPipelineDescription(
            source: source,
            encoder: encoder,
            sinkName: sinkName,
            queueName: queueName,
            reliableDelivery: reliableDelivery
          )
        }
      }
    }

    for description in descriptions {
        do {
          let pipeline = try Pipeline(description)
          let audioSink: AudioBufferSink?
          let packetSink: AudioPacketSink?
          let reliableCoordinator: LiveAudioReliablePacketCoordinator?

          reliableDelivery?.onCandidateStartForTesting?(pipeline, sinkName)

          if encoding == .raw {
            audioSink = try pipeline.audioBufferSink(named: sinkName)
            packetSink = nil
            reliableCoordinator = nil
          } else if let reliableDelivery {
            audioSink = nil
            packetSink = nil
            reliableCoordinator = try LiveAudioReliablePacketCoordinator(
              pipeline: pipeline,
              sinkName: sinkName,
              configuration: reliableDelivery
            )
          } else {
            audioSink = nil
            packetSink = try AudioPacketSink(pipeline: pipeline, name: sinkName)
            reliableCoordinator = nil
          }

          do {
            try pipeline.play()
          } catch {
            reliableCoordinator?.stopFromSource()
            pipeline.stop()
            throw error
          }

          return AudioSource(
            pipeline: pipeline,
            audioSink: audioSink,
            packetSink: packetSink,
            reliableCoordinator: reliableCoordinator,
            pipelineDescription: description,
            diagnostics: diagnostics,
            encoding: encoding
          )
        } catch {
          diagnostics.append("Failed: \(description) -> \(error)")
          continue
        }
    }

    throw AudioSource.AudioSourceError.noWorkingPipeline(diagnostics)
  }

  private func makeReliableDeliveryConfiguration(
    allowUnboundedForTesting: Bool = false
  ) throws
    -> AudioSourceReliableDeliveryConfiguration?
  {
    guard let request = reliableDeliveryRequest else {
      return nil
    }

    if encoding == .raw {
      throw AudioSource.AudioSourceError.invalidConfiguration(
        "Reliable live packet delivery requires encoded audio output; configure Opus or AAC encoding before build"
      )
    }

    if let maxTime = request.maxTime,
      !ReliableDurationConversion.validateNonNegative(maxTime)
    {
      throw AudioSource.AudioSourceError.invalidConfiguration(
        "Reliable delivery maxTime must be non-negative"
      )
    }

    let maxTimeNanoseconds = request.maxTime.map {
      ReliableDurationConversion.nanosecondsClampingNegativeToZero($0)
    }
    let maxBuffers = request.maxBuffers ?? 0
    let maxBytes = request.maxBytes ?? 0
    let maxTime = maxTimeNanoseconds ?? 0

    if !allowUnboundedForTesting && maxBuffers == 0 && maxBytes == 0 && maxTime == 0 {
      throw AudioSource.AudioSourceError.invalidConfiguration(
        "Reliable delivery requires at least one finite non-zero queue bound"
      )
    }

    return AudioSourceReliableDeliveryConfiguration(
      leaky: request.leaky,
      maxBuffers: maxBuffers,
      maxBytes: maxBytes,
      maxTimeNanoseconds: maxTime,
      firstSampleCapsProbe: reliableDeliveryHooks.firstSampleCapsProbe,
      candidateDescriptionsForTesting: reliableDeliveryHooks.candidateDescriptionsForTesting,
      onCandidateStartForTesting: reliableDeliveryHooks.onCandidateStartForTesting,
      onCleanupForTesting: reliableDeliveryHooks.onCleanupForTesting,
      sendEOSForTesting: reliableDeliveryHooks.sendEOSForTesting,
      finalizeErrorAfterSendEOSForTesting:
        reliableDeliveryHooks.finalizeErrorAfterSendEOSForTesting,
      suppressEOSCallbacksForTesting:
        reliableDeliveryHooks.suppressEOSCallbacksForTesting,
      probeState: AudioSourceReliablePacketProbeState()
    )
  }

  private func resolveSourceCandidates() -> [String] {
    switch selection {
    case .deviceIndex(let index):
      var candidates: [String] = []

      #if os(macOS) || os(iOS)
        candidates.append("osxaudiosrc device=\(index)")
      #elseif os(Linux)
        candidates.append("alsasrc device=hw:\(index),0")
        candidates.append("pulsesrc")
        candidates.append("pipewiresrc")
      #endif

      if index == 0 {
        candidates.append("autoaudiosrc")
      }

      if candidates.isEmpty {
        candidates.append("autoaudiosrc")
      }

      return candidates

    case .devicePath(let path):
      #if os(Linux)
        var candidates: [String] = []

        if path.hasPrefix("hw:") || path.hasPrefix("plughw:") || path == "default" {
          candidates.append("alsasrc device=\(path)")
        } else {
          candidates.append("pulsesrc device=\(path)")
          candidates.append("pipewiresrc device=\(path)")
          candidates.append("alsasrc device=\(path)")
        }

        candidates.append("autoaudiosrc")
        return candidates
      #else
        return ["autoaudiosrc"]
      #endif
    }
  }

  private func resolveEncoderCandidates() -> [String?] {
    switch encoding {
    case .raw:
      return [nil]

    case .opus(let bitrate):
      return ["opusenc bitrate=\(bitrate)"]

    case .aac(let bitrate):
      return [
        "avenc_aac bitrate=\(bitrate)",
        "faac bitrate=\(bitrate)",
        "voaacenc bitrate=\(bitrate)",
      ].map { Optional($0) }
    }
  }

  private func buildPipelineDescription(
    source: String,
    encoder: String?,
    sinkName: String,
    queueName: String,
    reliableDelivery: AudioSourceReliableDeliveryConfiguration?
  ) -> String {
    var parts: [String] = [source, "audioconvert", "audioresample"]

    let caps = buildCaps()
    if !caps.isEmpty {
      parts.append(caps)
    }

    if let reliableDelivery {
      parts.append(
        "queue name=\(queueName) leaky=\(reliableDelivery.leaky.rawValue) max-size-buffers=\(reliableDelivery.maxBuffers) max-size-bytes=\(reliableDelivery.maxBytes) max-size-time=\(reliableDelivery.maxTimeNanoseconds)"
      )
    }

    if let encoder {
      parts.append(encoder)
    }

    if reliableDelivery == nil {
      parts.append("appsink name=\(sinkName) sync=false drop=true max-buffers=1 emit-signals=true")
    } else {
      parts.append(
        "appsink name=\(sinkName) drop=false sync=false emit-signals=true enable-last-sample=false wait-on-eos=true max-buffers=1"
      )
    }

    return parts.joined(separator: " ! ")
  }

  private func buildCaps() -> String {
    var builder = CapsBuilder.audio()

    if let format {
      builder = builder.format(format)
    } else if encoding != .raw {
      builder = builder.format(.s16le)
    }

    if let sampleRate {
      builder = builder.rate(sampleRate)
    } else if encoding != .raw {
      builder = builder.rate(48_000)
    }

    if let channels {
      builder = builder.channels(channels)
    } else if encoding != .raw {
      builder = builder.channels(2)
    }

    return builder.build()
  }
}

private final class AudioPacketSink: @unchecked Sendable {
  private let element: Element

  private var appSink: UnsafeMutablePointer<GstAppSink> {
    UnsafeMutableRawPointer(element.element).assumingMemoryBound(to: GstAppSink.self)
  }

  init(pipeline: Pipeline, name: String) throws {
    guard let element = pipeline.element(named: name) else {
      throw GStreamerError.elementNotFound(name)
    }
    self.element = element
  }

  struct Packets: AsyncSequence {
    let sink: AudioPacketSink

    struct AsyncIterator: AsyncIteratorProtocol {
      let sink: AudioPacketSink

      mutating func next() async -> Buffer? {
        while !Task.isCancelled {
          if let sample = swift_gst_app_sink_try_pull_sample(sink.appSink, 100_000_000) {
            defer { swift_gst_sample_unref(UnsafeMutableRawPointer(sample)) }

            guard let gstBuffer = swift_gst_sample_get_buffer(UnsafeMutableRawPointer(sample))
            else {
              continue
            }

            let bufferSize = swift_gst_buffer_get_size(gstBuffer)
            guard bufferSize > 0 else { continue }

            _ = swift_gst_buffer_ref(gstBuffer)

            return Buffer(buffer: gstBuffer, ownsReference: true)
          }

          if swift_gst_app_sink_is_eos(sink.appSink) != 0 {
            break
          }

          await Task.yield()
        }

        return nil
      }
    }

    func makeAsyncIterator() -> AsyncIterator {
      AsyncIterator(sink: sink)
    }
  }

  func packets() -> AsyncStream<Buffer> {
    AsyncStream(
      bufferingPolicy: .bufferingNewest(MediaStreamBackpressure.encodedPacketsNewest)
    ) { continuation in
      let task = Task.detached { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }

        var iterator = Packets(sink: self).makeAsyncIterator()
        while let packet = await iterator.next() {
          continuation.yield(packet)
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private func stripTypeAnnotation(_ value: String) -> String {
  let trimmed = value.trimmingWhitespace()
  if trimmed.hasPrefix("(") {
    if let closeIndex = trimmed.firstIndex(of: ")") {
      let remainder = trimmed[trimmed.index(after: closeIndex)...]
      return String(remainder.trimmingWhitespace())
    }
  }
  return trimmed
}

private func parseIntList(from value: String) -> [Int] {
  let trimmed = value.trimmingWhitespace()

  if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
    let inner = trimmed.dropFirst().dropLast()
    return inner.split(separator: ",").compactMap { Int($0.trimmingWhitespace()) }
  }

  return [Int(trimmed)].compactMap { $0 }
}

private func parseAudioFormats(from value: String) -> [AudioFormat] {
  let trimmed = value.trimmingWhitespace()

  if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
    let inner = trimmed.dropFirst().dropLast()
    return
      inner
      .split(separator: ",")
      .map { String($0.trimmingWhitespace()) }
      .filter { !$0.isEmpty }
      .map { AudioFormat(string: $0) }
  }

  return [AudioFormat(string: trimmed)]
}
