import CGStreamer
import CGStreamerApp
import CGStreamerShim
import Foundation
import Synchronization

extension AudioSource {
  /// Create a convenience audio source from a local regular file.
  ///
  /// File-source reliable delivery is a non-core v0.1 layer over the low-level
  /// pipeline and appsink wrappers. File sources are finite and
  /// backpressureable, so they can be consumed with
  /// ``AudioFileSource/reliablePackets()``. Live microphone sources keep using
  /// ``AudioSource/packets()`` for realtime best-effort delivery unless they
  /// explicitly opt into reliable encoded live delivery.
  public static func file(path: String) -> AudioFileSourceBuilder {
    AudioFileSourceBuilder(path: path)
  }
}

/// Immutable convenience audio source backed by a local regular file.
///
/// `AudioFileSource` is a non-core v0.1 layer for finite file/decode workloads
/// where packet delivery can be backpressured and repeated. Use direct
/// ``Pipeline`` construction for custom file graphs.
public struct AudioFileSource: Sendable {
  private let configuration: AudioFileSourceConfiguration

  fileprivate init(configuration: AudioFileSourceConfiguration) {
    self.configuration = configuration
  }

  /// The output encoding configured for this source.
  public var encoding: AudioSource.Encoding {
    configuration.encoding
  }

  /// Return a fresh, single-consumer reliable packet sequence.
  ///
  /// Reliable delivery requires a source that can be backpressured. This file
  /// source is finite and consumer-driven; live capture sources should continue
  /// to use realtime APIs unless their upstream queue policy is explicit.
  public func reliablePackets() -> ReliablePackets<Buffer> {
    let source = AudioFileReliablePacketSource(configuration: configuration)
    return ReliablePackets<Buffer>(
      next: {
        try await source.next()
      },
      cancel: {
        source.cancel()
      }
    )
  }

  internal func reliableFirstSampleCapsForTesting() async throws -> String {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while clock.now < deadline {
      if let caps = configuration.probeState.firstSampleCaps() {
        return caps
      }
      try await Task.sleep(for: .milliseconds(10))
    }

    throw GStreamerError.busError(
      "First reliable packet caps were not observed",
      source: "ReliablePackets",
      debug: nil
    )
  }

  internal func reliablePacketRuntimeSnapshotForTesting() async
    -> ReliablePacketRuntimeSnapshotForTesting
  {
    configuration.probeState.snapshot()
  }

  internal func reliablePacketPipelineForTesting() async -> Pipeline? {
    configuration.probeState.pipeline()
  }

  internal func lossyPacketsForTesting() -> AsyncStream<Buffer> {
    let source = AudioFileLossyPacketSource(configuration: configuration)
    return source.packets()
  }
}

internal enum AudioFileReliableCallbackRegistrationFailureForTesting: Sendable, Equatable {
  case newSample
  case eos
  case bus

  fileprivate var errorMessage: String {
    switch self {
    case .newSample:
      return "Failed to connect appsink new-sample callback"
    case .eos:
      return "Failed to connect appsink eos callback"
    case .bus:
      return "Failed to connect bus sync-message observer"
    }
  }
}

/// Builder for a convenience audio file source that can produce reliable packets.
///
/// The builder composes decode, optional raw caps, optional encoding, and
/// appsink fragments for finite local files. It is part of the non-core v0.1
/// reliable delivery layer.
public struct AudioFileSourceBuilder: Sendable {
  private let path: String
  private var sampleRate: Int?
  private var channels: Int?
  private var format: AudioFormat?
  private var encoding: AudioSource.Encoding = .raw
  private var startupTimeoutNanoseconds: UInt64 = 5_000_000_000
  private var firstSampleCapsProbe: (@Sendable (String) -> Void)?
  private var candidateDescriptionsForTesting: [String]?
  private var candidateSinkNameForTesting: String?
  private var onCandidateStartForTesting: (@Sendable (Pipeline, String) -> Void)?
  private var afterCallbackRegistrationForTesting: (@Sendable (Pipeline, String) -> Void)?
  private var afterCandidatePlayForTesting: (@Sendable (Pipeline, String) -> Void)?
  private var onCleanupForTesting: (@Sendable () -> Void)?
  private var reliableCallbackRegistrationFailureForTesting:
    AudioFileReliableCallbackRegistrationFailureForTesting?

  fileprivate init(path: String) {
    self.path = path
  }

  /// Set the raw audio sample rate in Hz before packet output or encoding.
  public func withSampleRate(_ rate: Int) -> AudioFileSourceBuilder {
    var copy = self
    copy.sampleRate = rate
    return copy
  }

  /// Set the raw audio channel count before packet output or encoding.
  public func withChannels(_ channels: Int) -> AudioFileSourceBuilder {
    var copy = self
    copy.channels = channels
    return copy
  }

  /// Set the raw audio sample format before packet output or encoding.
  public func withFormat(_ format: AudioFormat) -> AudioFileSourceBuilder {
    var copy = self
    copy.format = format
    return copy
  }

  /// Set output encoding.
  public func withEncoding(_ encoding: AudioSource.Encoding) -> AudioFileSourceBuilder {
    var copy = self
    copy.encoding = encoding
    return copy
  }

  /// Encode decoded file audio to Opus packets.
  public func withOpusEncoding(bitrate: Int) -> AudioFileSourceBuilder {
    withEncoding(.opus(bitrate: bitrate))
  }

  /// Encode decoded file audio to AAC packets.
  public func withAACEncoding(bitrate: Int) -> AudioFileSourceBuilder {
    withEncoding(.aac(bitrate: bitrate))
  }

  /// Build an immutable, repeatable audio file source.
  public func build() throws -> AudioFileSource {
    let filePath = try validateFilePath(path)

    if let sampleRate, sampleRate <= 0 {
      throw GStreamerError.invalidArgument(
        parameter: "sampleRate",
        reason: "Sample rate must be positive"
      )
    }

    if let channels, channels <= 0 {
      throw GStreamerError.invalidArgument(
        parameter: "channels",
        reason: "Channel count must be positive"
      )
    }

    if case .opus(let bitrate) = encoding, bitrate <= 0 {
      throw GStreamerError.invalidArgument(
        parameter: "opusBitrate",
        reason: "Opus bitrate must be positive"
      )
    }

    if case .aac(let bitrate) = encoding, bitrate <= 0 {
      throw GStreamerError.invalidArgument(
        parameter: "aacBitrate",
        reason: "AAC bitrate must be positive"
      )
    }

    let configuration = AudioFileSourceConfiguration(
      path: filePath,
      uri: GstLaunch.fileURI(forPath: filePath),
      encoding: encoding,
      format: format ?? .s16le,
      sampleRate: sampleRate ?? 48_000,
      channels: channels ?? 2,
      startupTimeoutNanoseconds: startupTimeoutNanoseconds,
      firstSampleCapsProbe: firstSampleCapsProbe,
      candidateDescriptionsForTesting: candidateDescriptionsForTesting,
      candidateSinkNameForTesting: candidateSinkNameForTesting,
      onCandidateStartForTesting: onCandidateStartForTesting,
      afterCallbackRegistrationForTesting: afterCallbackRegistrationForTesting,
      afterCandidatePlayForTesting: afterCandidatePlayForTesting,
      onCleanupForTesting: onCleanupForTesting,
      reliableCallbackRegistrationFailureForTesting: reliableCallbackRegistrationFailureForTesting,
      probeState: AudioFileReliablePacketProbeState()
    )
    return AudioFileSource(configuration: configuration)
  }

  internal func _withReliablePacketStartupTimeoutNanoseconds(_ nanoseconds: UInt64)
    -> AudioFileSourceBuilder
  {
    var copy = self
    copy.startupTimeoutNanoseconds = nanoseconds
    return copy
  }

  internal func withReliablePacketStartupTimeoutForTesting(_ duration: Duration)
    -> AudioFileSourceBuilder
  {
    _withReliablePacketStartupTimeoutNanoseconds(duration.nanosecondsForReliablePackets)
  }

  internal func _withFirstSampleCapsProbe(
    _ probe: (@Sendable (String) -> Void)?
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.firstSampleCapsProbe = probe
    return copy
  }

  internal func withReliablePacketCandidateDescriptionsForTesting(
    _ descriptions: [String],
    sinkName: String
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.candidateDescriptionsForTesting = descriptions
    copy.candidateSinkNameForTesting = sinkName
    return copy
  }

  internal func withReliablePacketOnCandidateStartForTesting(
    _ callback: @escaping @Sendable (Pipeline, String) -> Void
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.onCandidateStartForTesting = callback
    return copy
  }

  internal func withReliablePacketAfterCallbackRegistrationForTesting(
    _ callback: @escaping @Sendable (Pipeline, String) -> Void
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.afterCallbackRegistrationForTesting = callback
    return copy
  }

  internal func withReliablePacketAfterCandidatePlayForTesting(
    _ callback: @escaping @Sendable (Pipeline, String) -> Void
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.afterCandidatePlayForTesting = callback
    return copy
  }

  internal func withReliablePacketOnCleanupForTesting(
    _ callback: @escaping @Sendable () -> Void
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.onCleanupForTesting = callback
    return copy
  }

  internal func withReliablePacketCallbackRegistrationFailureForTesting(
    _ failure: AudioFileReliableCallbackRegistrationFailureForTesting?
  ) -> AudioFileSourceBuilder {
    var copy = self
    copy.reliableCallbackRegistrationFailureForTesting = failure
    return copy
  }

  private func validateFilePath(_ path: String) throws -> String {
    let trimmed = path.trimmingWhitespace()
    guard !trimmed.isEmpty else {
      throw GStreamerError.invalidArgument(
        parameter: "path",
        reason: "Path must not be empty"
      )
    }

    let url = URL(fileURLWithPath: path).standardizedFileURL
    let normalizedPath = url.path
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory) else {
      throw GStreamerError.invalidArgument(
        parameter: "path",
        reason: "Path does not exist"
      )
    }
    guard !isDirectory.boolValue else {
      throw GStreamerError.invalidArgument(
        parameter: "path",
        reason: "Path must refer to a regular file"
      )
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: normalizedPath)
    guard attributes?[.type] as? FileAttributeType == .typeRegular else {
      throw GStreamerError.invalidArgument(
        parameter: "path",
        reason: "Path must refer to a regular file"
      )
    }
    guard FileManager.default.isReadableFile(atPath: normalizedPath) else {
      throw GStreamerError.invalidArgument(
        parameter: "path",
        reason: "Path must be readable"
      )
    }
    return normalizedPath
  }
}

private struct AudioFileSourceConfiguration: Sendable {
  let path: String
  let uri: String
  let encoding: AudioSource.Encoding
  let format: AudioFormat
  let sampleRate: Int
  let channels: Int
  let startupTimeoutNanoseconds: UInt64
  let firstSampleCapsProbe: (@Sendable (String) -> Void)?
  let candidateDescriptionsForTesting: [String]?
  let candidateSinkNameForTesting: String?
  let onCandidateStartForTesting: (@Sendable (Pipeline, String) -> Void)?
  let afterCallbackRegistrationForTesting: (@Sendable (Pipeline, String) -> Void)?
  let afterCandidatePlayForTesting: (@Sendable (Pipeline, String) -> Void)?
  let onCleanupForTesting: (@Sendable () -> Void)?
  let reliableCallbackRegistrationFailureForTesting:
    AudioFileReliableCallbackRegistrationFailureForTesting?
  let probeState: AudioFileReliablePacketProbeState
}

internal struct ReliablePacketRuntimeSnapshotForTesting: Sendable {
  let newSampleHandlerCount: Int
  let pendingContinuationCount: Int
  let cleanupAcknowledgementCount: Int
  let finalized: Bool
  let stopped: Bool
  let activePipeline: Pipeline?
  let activeSequence: Bool

  init(
    newSampleHandlerCount: Int,
    pendingContinuationCount: Int,
    cleanupAcknowledgementCount: Int,
    finalized: Bool = false,
    stopped: Bool = false,
    activePipeline: Pipeline? = nil,
    activeSequence: Bool = false
  ) {
    self.newSampleHandlerCount = newSampleHandlerCount
    self.pendingContinuationCount = pendingContinuationCount
    self.cleanupAcknowledgementCount = cleanupAcknowledgementCount
    self.finalized = finalized
    self.stopped = stopped
    self.activePipeline = activePipeline
    self.activeSequence = activeSequence
  }
}

private final class AudioFileReliablePacketProbeState: @unchecked Sendable {
  private struct State {
    var firstSampleCaps: String?
    var pipeline: Pipeline?
    var newSampleHandlerCount = 0
    var pendingContinuationCount = 0
    var cleanupAcknowledgementCount = 0
  }

  private let state = Mutex(State())

  func recordFirstSampleCaps(_ caps: String) {
    state.withLock { state in
      if state.firstSampleCaps == nil {
        state.firstSampleCaps = caps
      }
    }
  }

  func firstSampleCaps() -> String? {
    state.withLock { $0.firstSampleCaps }
  }

  func recordPipeline(_ pipeline: Pipeline) {
    state.withLock { $0.pipeline = pipeline }
  }

  func clearPipeline(_ pipeline: Pipeline) {
    state.withLock { state in
      if state.pipeline === pipeline {
        state.pipeline = nil
      }
    }
  }

  func pipeline() -> Pipeline? {
    state.withLock { $0.pipeline }
  }

  func incrementNewSampleHandlerCount() {
    state.withLock { $0.newSampleHandlerCount += 1 }
  }

  func decrementNewSampleHandlerCount() {
    state.withLock { state in
      state.newSampleHandlerCount = max(0, state.newSampleHandlerCount - 1)
    }
  }

  func setPendingContinuationCount(_ count: Int) {
    state.withLock { $0.pendingContinuationCount = count }
  }

  func acknowledgeCleanup() {
    state.withLock { $0.cleanupAcknowledgementCount += 1 }
  }

  func snapshot() -> ReliablePacketRuntimeSnapshotForTesting {
    state.withLock {
      ReliablePacketRuntimeSnapshotForTesting(
        newSampleHandlerCount: $0.newSampleHandlerCount,
        pendingContinuationCount: $0.pendingContinuationCount,
        cleanupAcknowledgementCount: $0.cleanupAcknowledgementCount
      )
    }
  }
}

private extension Duration {
  var nanosecondsForReliablePackets: UInt64 {
    ReliableDurationConversion.nanosecondsClampingNegativeToZero(self)
  }
}

private struct AudioFilePipelineCandidate: Sendable {
  let description: String
  let sinkName: String
}

private final class AudioFileReliablePacketSource: @unchecked Sendable {
  private enum PullPacketResult {
    case packet(Buffer)
    case skippedEmptySample
    case noSample
  }

  private struct State {
    var nextCandidateIndex = 0
    var active: ActiveCandidate?
    var pending: CheckedContinuation<Bool, Error>?
    var sampleGeneration: UInt64 = 0
    var eos = false
    var terminalError: Error?
    var shuttingDown = false
    var deliveredFirstPacket = false
    var lastStartupFailure: Error?
    var reportedFirstSampleCaps = false
  }

  private let configuration: AudioFileSourceConfiguration
  private let candidates: [AudioFilePipelineCandidate]
  private let state = Mutex(State())

  init(configuration: AudioFileSourceConfiguration) {
    self.configuration = configuration
    self.candidates = Self.buildCandidates(for: configuration)
  }

  deinit {
    cancel()
  }

  func next() async throws -> Buffer? {
    while true {
      try Task.checkCancellation()

      guard let active = try activateCandidateIfNeeded() else {
        return try throwExhaustion()
      }

      do {
        if let packet = try await nextPacket(from: active) {
          return packet
        }

        let hadDeliveredPacket = hasDeliveredFirstPacket()
        stopActiveCandidate(active)
        if hadDeliveredPacket {
          return nil
        }
        recordCleanEOSBeforeFirstPacket()
      } catch is CancellationError {
        stopActiveCandidate(active)
        throw CancellationError()
      } catch {
        let hadDeliveredPacket = hasDeliveredFirstPacket()
        stopActiveCandidate(active)
        if hadDeliveredPacket {
          throw error
        }
        recordStartupFailure(error)
      }
    }
  }

  func cancel() {
    let cleanup = state.withLock { state -> (ActiveCandidate?, CheckedContinuation<Bool, Error>?) in
      guard !state.shuttingDown else {
        return (nil, nil)
      }
      state.shuttingDown = true
      let active = state.active
      state.active = nil
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        configuration.probeState.setPendingContinuationCount(0)
      }
      return (active, pending)
    }

    cleanup.0?.disconnectNewSample()
    cleanup.1?.resume(throwing: CancellationError())
    cleanup.0?.stop()
  }

  private func activateCandidateIfNeeded() throws -> ActiveCandidate? {
    if let active = state.withLock({ $0.active }) {
      return active
    }

    let candidate: AudioFilePipelineCandidate? = state.withLock { state in
      guard !state.shuttingDown else { return nil }
      guard state.nextCandidateIndex < candidates.count else { return nil }
      let candidate = candidates[state.nextCandidateIndex]
      state.nextCandidateIndex += 1
      state.eos = false
      state.terminalError = nil
      state.sampleGeneration = 0
      return candidate
    }

    guard let candidate else {
      if state.withLock({ $0.shuttingDown }) {
        throw CancellationError()
      }
      return nil
    }

    let active: ActiveCandidate
    do {
      active = try ActiveCandidate(
        candidate: candidate,
        owner: self,
        configuration: configuration
      )
    } catch GStreamerError.parsePipeline(let message) {
      notifyCandidateStartForParseFailure(candidate)
      recordStartupFailure(
        GStreamerError.parsePipeline("\(message) while parsing candidate: \(candidate.description)")
      )
      return try activateCandidateIfNeeded()
    } catch {
      recordStartupFailure(error)
      return try activateCandidateIfNeeded()
    }

    let activated = state.withLock { state in
      guard !state.shuttingDown else {
        return false
      }
      state.active = active
      state.eos = false
      state.terminalError = nil
      state.sampleGeneration = 0
      return true
    }
    guard activated else {
      active.stop()
      throw CancellationError()
    }

    do {
      try active.play()
      guard isCurrent(active) else {
        active.stop()
        throw CancellationError()
      }
      configuration.afterCandidatePlayForTesting?(active.pipeline, candidate.sinkName)
    } catch is CancellationError {
      stopActiveCandidate(active)
      throw CancellationError()
    } catch {
      stopActiveCandidate(active)
      recordStartupFailure(error)
      return try activateCandidateIfNeeded()
    }

    return active
  }

  private func nextPacket(from active: ActiveCandidate) async throws -> Buffer? {
    let timeoutTask = makeStartupTimeoutTask(for: active)
    defer {
      timeoutTask?.cancel()
    }

    while true {
      try Task.checkCancellation()
      if try terminalStateAllowsPull(for: active) == false {
        return nil
      }

      let generation = sampleGeneration()

      switch try pullPacket(from: active) {
      case .packet(let packet):
        try markFirstPacketDelivered(from: active)
        return packet

      case .skippedEmptySample:
        await Task.yield()
        if try terminalStateAllowsPull(for: active) == false {
          return nil
        }
        continue

      case .noSample:
        if try await waitForEvent(after: generation) == false {
          return nil
        }
      }
    }
  }

  private func makeStartupTimeoutTask(for active: ActiveCandidate) -> Task<Void, Never>? {
    guard !hasDeliveredFirstPacket() else {
      return nil
    }
    let timeout = configuration.startupTimeoutNanoseconds
    guard timeout > 0 else {
      return nil
    }

    return Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: timeout)
      } catch {
        return
      }
      self?.reportStartupTimeoutIfStillBeforeFirstPacket(candidateID: active.id)
    }
  }

  private func pullPacket(from active: ActiveCandidate) throws -> PullPacketResult {
    guard isCurrent(active) else {
      throw CancellationError()
    }

    guard let sample = swift_gst_app_sink_try_pull_sample(active.appSink, 0) else {
      return .noSample
    }
    defer { swift_gst_sample_unref(UnsafeMutableRawPointer(sample)) }

    if shouldReportFirstSampleCaps(),
      let caps = swift_gst_sample_get_caps(UnsafeMutableRawPointer(sample)),
      let capsString = GLibString.takeOwnership(swift_gst_caps_to_string(caps))
    {
      configuration.probeState.recordFirstSampleCaps(capsString)
      configuration.firstSampleCapsProbe?(capsString)
    }

    guard let gstBuffer = swift_gst_sample_get_buffer(UnsafeMutableRawPointer(sample)) else {
      throw GStreamerError.bufferMapFailed
    }

    guard swift_gst_buffer_get_size(gstBuffer) > 0 else {
      return .skippedEmptySample
    }

    _ = swift_gst_buffer_ref(gstBuffer)
    return .packet(Buffer(buffer: gstBuffer, ownsReference: true))
  }

  private func waitForEvent(after generation: UInt64) async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      let immediate = state.withLock { state -> Result<Bool, Error>? in
        if state.shuttingDown {
          return .failure(CancellationError())
        }
        if let terminalError = state.terminalError {
          return .failure(terminalError)
        }
        if state.eos {
          return .success(false)
        }
        if state.sampleGeneration != generation {
          return .success(true)
        }
        if state.pending != nil {
          return .failure(
            GStreamerError.invalidArgument(
              parameter: "ReliablePackets.AsyncIterator",
              reason: "Concurrent next() calls are unsupported"
            )
          )
        }
        state.pending = continuation
        configuration.probeState.setPendingContinuationCount(1)
        return nil
      }

      if let immediate {
        continuation.resume(with: immediate)
      }
    }
  }

  private func sampleGeneration() -> UInt64 {
    state.withLock { $0.sampleGeneration }
  }

  private func isCurrent(_ active: ActiveCandidate) -> Bool {
    state.withLock { state in
      state.active === active && !state.shuttingDown
    }
  }

  private func terminalStateAllowsPull(for active: ActiveCandidate) throws -> Bool {
    let result = state.withLock { state -> Result<Bool, Error> in
      guard state.active === active, !state.shuttingDown else {
        return .failure(CancellationError())
      }
      if let terminalError = state.terminalError {
        return .failure(terminalError)
      }
      if state.eos {
        // EOS can arrive while appsink still has queued samples. Observe it
        // here, but let the next nonblocking pull drain any queued packet; the
        // no-sample path below terminates via waitForEvent(after:).
        return .success(true)
      }
      return .success(true)
    }

    return try result.get()
  }

  private func markFirstPacketDelivered(from active: ActiveCandidate) throws {
    let error = state.withLock { state -> Error? in
      guard state.active?.id == active.id, !state.shuttingDown else {
        return CancellationError()
      }
      if let terminalError = state.terminalError {
        return terminalError
      }
      state.deliveredFirstPacket = true
      return nil
    }

    if let error {
      throw error
    }
  }

  private func hasDeliveredFirstPacket() -> Bool {
    state.withLock { $0.deliveredFirstPacket }
  }

  private func shouldReportFirstSampleCaps() -> Bool {
    state.withLock { state in
      guard !state.reportedFirstSampleCaps else {
        return false
      }
      state.reportedFirstSampleCaps = true
      return true
    }
  }

  private func stopActiveCandidate(_ active: ActiveCandidate) {
    let shouldStop = state.withLock { state in
      guard state.active === active else {
        return false
      }
      state.active = nil
      state.pending = nil
      configuration.probeState.setPendingContinuationCount(0)
      state.eos = false
      state.terminalError = nil
      state.sampleGeneration = 0
      return true
    }

    if shouldStop {
      active.stop()
    }
  }

  private func recordStartupFailure(_ error: Error) {
    state.withLock { $0.lastStartupFailure = error }
  }

  private func recordCleanEOSBeforeFirstPacket() {
  }

  private func throwExhaustion() throws -> Buffer? {
    if let failure = state.withLock({ $0.lastStartupFailure }) {
      throw failure
    }
    throw GStreamerError.busError(
      "No decodable audio packets",
      source: "ReliablePackets",
      debug: nil
    )
  }

  fileprivate func reportNewSample(candidateID: UInt64) {
    let pending = state.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard state.active?.id == candidateID, !state.shuttingDown else {
        return nil
      }
      state.sampleGeneration &+= 1
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        configuration.probeState.setPendingContinuationCount(0)
      }
      return pending
    }
    pending?.resume(returning: true)
  }

  fileprivate func reportEOS(candidateID: UInt64) {
    let pending = state.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard state.active?.id == candidateID, !state.shuttingDown else {
        return nil
      }
      state.eos = true
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        configuration.probeState.setPendingContinuationCount(0)
      }
      return pending
    }
    pending?.resume(returning: true)
  }

  fileprivate func reportBusError(candidateID: UInt64, error: GStreamerError) {
    let pending = state.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard state.active?.id == candidateID, !state.shuttingDown else {
        return nil
      }
      state.terminalError = error
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        configuration.probeState.setPendingContinuationCount(0)
      }
      return pending
    }
    pending?.resume(throwing: error)
  }

  private func reportStartupTimeoutIfStillBeforeFirstPacket(candidateID: UInt64) {
    let timeout = state.withLock {
      state -> (pending: CheckedContinuation<Bool, Error>?, error: GStreamerError)? in
      guard state.active?.id == candidateID,
        !state.shuttingDown,
        !state.deliveredFirstPacket
      else {
        return nil
      }

      let error = GStreamerError.busError(
        "Reliable packet startup timed out",
        source: "ReliablePackets",
        debug: "No decodable audio packet arrived before startup timeout"
      )
      state.terminalError = error
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        configuration.probeState.setPendingContinuationCount(0)
      }
      return (pending, error)
    }

    if let timeout {
      timeout.pending?.resume(throwing: timeout.error)
    }
  }

  private func notifyCandidateStartForParseFailure(_ candidate: AudioFilePipelineCandidate) {
    guard let onCandidateStart = configuration.onCandidateStartForTesting else {
      return
    }
    guard let placeholder = try? Pipeline("fakesrc num-buffers=0 ! fakesink") else {
      return
    }
    onCandidateStart(placeholder, candidate.sinkName)
    placeholder.stop()
  }

  private static func buildCandidates(
    for configuration: AudioFileSourceConfiguration
  ) -> [AudioFilePipelineCandidate] {
    if let descriptions = configuration.candidateDescriptionsForTesting {
      let sinkName = configuration.candidateSinkNameForTesting ?? "reliablePacketSink"
      return descriptions.map {
        AudioFilePipelineCandidate(description: $0, sinkName: sinkName)
      }
    }

    let sinkName = "reliablePacketSink\(UInt32.random(in: 0...UInt32.max))"
    let caps = CapsBuilder.audio()
      .format(configuration.format)
      .rate(configuration.sampleRate)
      .channels(configuration.channels)
      .build()

    return encoderCandidates(for: configuration.encoding).map { encoder in
      var parts = [
        "uridecodebin \(GstLaunch.property("uri", value: configuration.uri))",
        "audio/x-raw",
        "audioconvert",
        "audioresample",
        caps,
      ]

      if let encoder {
        parts.append(encoder)
      }

      parts.append(
        "appsink name=\(sinkName) drop=false max-buffers=8 sync=false emit-signals=true enable-last-sample=false wait-on-eos=false"
      )

      return AudioFilePipelineCandidate(
        description: parts.joined(separator: " ! "),
        sinkName: sinkName
      )
    }
  }

  private static func encoderCandidates(for encoding: AudioSource.Encoding) -> [String?] {
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
      ]
    }
  }
}

private final class AudioFileLossyPacketSource: @unchecked Sendable {
  private let configuration: AudioFileSourceConfiguration

  init(configuration: AudioFileSourceConfiguration) {
    self.configuration = configuration
  }

  func packets() -> AsyncStream<Buffer> {
    AsyncStream(
      bufferingPolicy: .bufferingNewest(MediaStreamBackpressure.encodedPacketsNewest)
    ) { continuation in
      let task = Task.detached { [configuration] in
        do {
          let candidate = Self.buildCandidate(for: configuration)
          let pipeline = try Pipeline(candidate.description)
          defer { pipeline.stop() }

          guard let element = pipeline.element(named: candidate.sinkName) else {
            continuation.finish()
            return
          }

          let appSink = UnsafeMutableRawPointer(element.element).assumingMemoryBound(to: GstAppSink.self)
          try pipeline.play()

          while !Task.isCancelled {
            if let sample = swift_gst_app_sink_try_pull_sample(appSink, 100_000_000) {
              defer { swift_gst_sample_unref(UnsafeMutableRawPointer(sample)) }
              guard let gstBuffer = swift_gst_sample_get_buffer(UnsafeMutableRawPointer(sample)) else {
                continue
              }
              guard swift_gst_buffer_get_size(gstBuffer) > 0 else {
                continue
              }
              _ = swift_gst_buffer_ref(gstBuffer)
              continuation.yield(Buffer(buffer: gstBuffer, ownsReference: true))
            }

            if swift_gst_app_sink_is_eos(appSink) != 0 {
              break
            }
          }
        } catch {
          // Testing-only lossy contrast stream mirrors realtime best effort:
          // build/runtime failures end the stream instead of throwing.
        }

        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private static func buildCandidate(
    for configuration: AudioFileSourceConfiguration
  ) -> AudioFilePipelineCandidate {
    let sinkName = "lossyPacketSink\(UInt32.random(in: 0...UInt32.max))"
    let caps = CapsBuilder.audio()
      .format(configuration.format)
      .rate(configuration.sampleRate)
      .channels(configuration.channels)
      .build()

    var parts = [
      "uridecodebin \(GstLaunch.property("uri", value: configuration.uri))",
      "audio/x-raw",
      "audioconvert",
      "audioresample",
      caps,
    ]

    if let encoder = encoderCandidate(for: configuration.encoding) {
      parts.append(encoder)
    }

    parts.append(
      "appsink name=\(sinkName) sync=false drop=true max-buffers=1 emit-signals=true enable-last-sample=false wait-on-eos=false"
    )

    return AudioFilePipelineCandidate(description: parts.joined(separator: " ! "), sinkName: sinkName)
  }

  private static func encoderCandidate(for encoding: AudioSource.Encoding) -> String? {
    switch encoding {
    case .raw:
      return nil
    case .opus(let bitrate):
      return "opusenc bitrate=\(bitrate)"
    case .aac(let bitrate):
      return "avenc_aac bitrate=\(bitrate)"
    }
  }
}

private final class ActiveCandidate: @unchecked Sendable {
  private struct CallbackState {
    var stopped = false
    var newSampleDisconnected = false
    var eosDisconnected = false
    var busDisconnected = false
  }

  let id: UInt64
  let pipeline: Pipeline
  let sinkElement: Element
  let bus: Bus

  private let newSampleRegistration: OpaquePointer?
  private let eosRegistration: OpaquePointer?
  private let busRegistration: OpaquePointer?
  private let probeState: AudioFileReliablePacketProbeState
  private let onCleanupForTesting: (@Sendable () -> Void)?
  private let callbackState = Mutex(CallbackState())

  var appSink: UnsafeMutablePointer<GstAppSink> {
    UnsafeMutableRawPointer(sinkElement.element).assumingMemoryBound(to: GstAppSink.self)
  }

  init(
    candidate: AudioFilePipelineCandidate,
    owner: AudioFileReliablePacketSource,
    configuration: AudioFileSourceConfiguration
  ) throws {
    self.id = UInt64.random(in: 1...UInt64.max)
    self.pipeline = try Pipeline(candidate.description)
    configuration.onCandidateStartForTesting?(pipeline, candidate.sinkName)
    guard let sinkElement = pipeline.element(named: candidate.sinkName) else {
      throw GStreamerError.elementNotFound(candidate.sinkName)
    }
    let callbackBus = pipeline.bus
    self.sinkElement = sinkElement
    self.bus = callbackBus
    self.probeState = configuration.probeState
    self.onCleanupForTesting = configuration.onCleanupForTesting

    let context = AudioFileReliableCallbackContext(source: owner, candidateID: id)
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()

    let appSink = UnsafeMutableRawPointer(sinkElement.element).assumingMemoryBound(to: GstAppSink.self)
    let registrations = try withExtendedLifetime(context) {
      () throws -> (newSample: OpaquePointer, eos: OpaquePointer, bus: OpaquePointer) in
      guard
        let newSampleRegistration = configuration.reliableCallbackRegistrationFailureForTesting == .newSample
          ? nil
          : swift_gst_app_sink_connect_new_sample(
              appSink,
              audioFileReliableNewSampleCallback,
              contextPointer,
              audioFileReliableRetainContext,
              audioFileReliableReleaseContext
            )
      else {
        throw GStreamerError.busError(
          AudioFileReliableCallbackRegistrationFailureForTesting.newSample.errorMessage,
          source: "ReliablePackets",
          debug: nil
        )
      }
      configuration.probeState.incrementNewSampleHandlerCount()

      guard
        let eosRegistration = configuration.reliableCallbackRegistrationFailureForTesting == .eos
          ? nil
          : swift_gst_app_sink_connect_eos(
              appSink,
              audioFileReliableEOSCallback,
              contextPointer,
              audioFileReliableRetainContext,
              audioFileReliableReleaseContext
            )
      else {
        swift_gst_callback_registration_disconnect(newSampleRegistration)
        configuration.probeState.decrementNewSampleHandlerCount()
        throw GStreamerError.busError(
          AudioFileReliableCallbackRegistrationFailureForTesting.eos.errorMessage,
          source: "ReliablePackets",
          debug: nil
        )
      }

      guard
        let busRegistration = configuration.reliableCallbackRegistrationFailureForTesting == .bus
          ? nil
          : swift_gst_bus_connect_sync_message_observer(
              callbackBus._bus,
              audioFileReliableBusSyncMessageCallback,
              contextPointer,
              audioFileReliableRetainContext,
              audioFileReliableReleaseContext
            )
      else {
        swift_gst_callback_registration_disconnect(newSampleRegistration)
        configuration.probeState.decrementNewSampleHandlerCount()
        swift_gst_callback_registration_disconnect(eosRegistration)
        throw GStreamerError.busError(
          AudioFileReliableCallbackRegistrationFailureForTesting.bus.errorMessage,
          source: "ReliablePackets",
          debug: nil
        )
      }

      return (newSampleRegistration, eosRegistration, busRegistration)
    }

    self.newSampleRegistration = registrations.newSample
    self.eosRegistration = registrations.eos
    self.busRegistration = registrations.bus
    configuration.probeState.recordPipeline(pipeline)
    configuration.afterCallbackRegistrationForTesting?(pipeline, candidate.sinkName)
  }

  deinit {
    stop()
  }

  func play() throws {
    try pipeline.play()
  }

  func disconnectNewSample() {
    let shouldDisconnect = callbackState.withLock { state in
      guard !state.newSampleDisconnected else { return false }
      state.newSampleDisconnected = true
      return true
    }
    if shouldDisconnect {
      swift_gst_callback_registration_disconnect(newSampleRegistration)
      probeState.decrementNewSampleHandlerCount()
    }
  }

  func stop() {
    let disconnects = callbackState.withLock { state in
      guard !state.stopped else {
        return (newSample: false, eos: false, bus: false)
      }

      state.stopped = true
      let disconnects = (
        newSample: !state.newSampleDisconnected,
        eos: !state.eosDisconnected,
        bus: !state.busDisconnected
      )
      state.newSampleDisconnected = true
      state.eosDisconnected = true
      state.busDisconnected = true
      return disconnects
    }

    guard disconnects.newSample || disconnects.eos || disconnects.bus else {
      return
    }

    if disconnects.newSample {
      swift_gst_callback_registration_disconnect(newSampleRegistration)
      probeState.decrementNewSampleHandlerCount()
    }
    if disconnects.eos {
      swift_gst_callback_registration_disconnect(eosRegistration)
    }
    if disconnects.bus {
      swift_gst_callback_registration_disconnect(busRegistration)
    }
    pipeline.stop()
    gst_bus_set_flushing(bus._bus, 0)
    probeState.clearPipeline(pipeline)
    probeState.setPendingContinuationCount(0)
    probeState.acknowledgeCleanup()
    onCleanupForTesting?()
  }
}

private final class AudioFileReliableCallbackContext: @unchecked Sendable {
  let source: AudioFileReliablePacketSource
  let candidateID: UInt64

  init(source: AudioFileReliablePacketSource, candidateID: UInt64) {
    self.source = source
    self.candidateID = candidateID
  }
}

private func audioFileReliableRetainContext(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  _ = Unmanaged<AudioFileReliableCallbackContext>.fromOpaque(context).retain()
}

private func audioFileReliableReleaseContext(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<AudioFileReliableCallbackContext>.fromOpaque(context).release()
}

private func audioFileReliableNewSampleCallback(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  let callbackContext = Unmanaged<AudioFileReliableCallbackContext>
    .fromOpaque(context)
    .takeUnretainedValue()
  callbackContext.source.reportNewSample(candidateID: callbackContext.candidateID)
}

private func audioFileReliableEOSCallback(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  let callbackContext = Unmanaged<AudioFileReliableCallbackContext>
    .fromOpaque(context)
    .takeUnretainedValue()
  callbackContext.source.reportEOS(candidateID: callbackContext.candidateID)
}

private func audioFileReliableBusSyncMessageCallback(
  _ message: UnsafeMutablePointer<GstMessage>?,
  _ context: UnsafeMutableRawPointer?
) {
  guard let message, let context else {
    return
  }

  let callbackContext = Unmanaged<AudioFileReliableCallbackContext>
    .fromOpaque(context)
    .takeUnretainedValue()

  switch swift_gst_message_type(message) {
  case GST_MESSAGE_ERROR:
    var errorString: UnsafeMutablePointer<CChar>?
    var debugString: UnsafeMutablePointer<CChar>?
    swift_gst_message_parse_error(message, &errorString, &debugString)

    let sourceName = GLibString.takeOwnership(
      swift_gst_message_src(message).flatMap { gst_object_get_name($0) }
    )
    let error = GStreamerError.busError(
      GLibString.takeOwnership(errorString) ?? "Unknown error",
      source: sourceName,
      debug: GLibString.takeOwnership(debugString)
    )
    callbackContext.source.reportBusError(
      candidateID: callbackContext.candidateID,
      error: error
    )

  case GST_MESSAGE_EOS:
    callbackContext.source.reportEOS(candidateID: callbackContext.candidateID)

  default:
    break
  }
}
