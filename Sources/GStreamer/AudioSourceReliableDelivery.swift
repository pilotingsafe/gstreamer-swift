import CGStreamer
import CGStreamerApp
import CGStreamerShim
import Synchronization

internal struct AudioSourceReliableDeliveryRequest: Sendable {
  let leaky: QueueLeaky
  let maxBuffers: UInt?
  let maxBytes: UInt?
  let maxTime: Duration?
}

internal struct AudioSourceReliableDeliveryHooks: Sendable {
  var firstSampleCapsProbe: (@Sendable (String) -> Void)?
  var candidateDescriptionsForTesting: [String]?
  var candidateSinkNameForTesting: String?
  var candidateQueueNameForTesting: String?
  var onCandidateStartForTesting: (@Sendable (Pipeline, String) -> Void)?
  var onCleanupForTesting: (@Sendable () -> Void)?
  var sendEOSForTesting: (@Sendable (Pipeline) -> Bool)?
  var finalizeErrorAfterSendEOSForTesting: (@Sendable () -> GStreamerError?)?
  var suppressEOSCallbacksForTesting = false
}

internal struct AudioSourceReliableDeliveryConfiguration: Sendable {
  let leaky: QueueLeaky
  let maxBuffers: UInt
  let maxBytes: UInt
  let maxTimeNanoseconds: UInt64
  let firstSampleCapsProbe: (@Sendable (String) -> Void)?
  let candidateDescriptionsForTesting: [String]?
  let onCandidateStartForTesting: (@Sendable (Pipeline, String) -> Void)?
  let onCleanupForTesting: (@Sendable () -> Void)?
  let sendEOSForTesting: (@Sendable (Pipeline) -> Bool)?
  let finalizeErrorAfterSendEOSForTesting: (@Sendable () -> GStreamerError?)?
  let suppressEOSCallbacksForTesting: Bool
  let probeState: AudioSourceReliablePacketProbeState
}

internal struct AudioSourceShutdownSnapshot: Sendable {
  let finalized: Bool
  let stopped: Bool
}

internal final class AudioSourceShutdownCoordinator: @unchecked Sendable {
  private struct StoredFinalizeResult: @unchecked Sendable {
    let result: Result<Void, Error>
  }

  private struct State: Sendable {
    var stopped = false
    var finalized = false
    var finalizing = false
    var finalizeResult: StoredFinalizeResult?
    var finalizeWaiters: [CheckedContinuation<Void, Error>] = []
    var injectedFinalizeError: GStreamerError?
  }

  private enum FinalizeStartDecision {
    case replay(StoredFinalizeResult)
    case wait
    case alreadyStopped
    case start
  }

  private enum FinalizeWaitDecision {
    case wait
    case replay(StoredFinalizeResult)
    case resumeSuccess
  }

  private let state = Mutex(State())

  func stop(
    pipeline: Pipeline,
    reliableCoordinator: LiveAudioReliablePacketCoordinator?
  ) {
    let shouldStop = state.withLock { state in
      guard !state.stopped else { return false }
      state.stopped = true
      return true
    }

    guard shouldStop else { return }
    reliableCoordinator?.stopFromSource()
    pipeline.stop()
    gst_bus_set_flushing(pipeline.bus._bus, 0)
  }

  func finalize(
    pipeline: Pipeline,
    reliableCoordinator: LiveAudioReliablePacketCoordinator?,
    timeout: Duration
  ) async throws {
    let decision = state.withLock { state -> FinalizeStartDecision in
      if let finalizeResult = state.finalizeResult {
        return .replay(finalizeResult)
      }
      if state.finalizing {
        return .wait
      }
      if state.stopped || state.finalized {
        return .alreadyStopped
      }
      state.finalizing = true
      return .start
    }

    switch decision {
    case .replay(let finalizeResult):
      try finalizeResult.result.get()
      return
    case .wait:
      try await waitForInFlightFinalize()
      return
    case .alreadyStopped:
      return
    case .start:
      break
    }

    do {
      try await Self.performFinalize(
        pipeline: pipeline,
        reliableCoordinator: reliableCoordinator,
        timeout: timeout,
        injectedError: takeInjectedFinalizeError()
      )
      completeFinalize(with: .success(()))
    } catch {
      completeFinalize(with: .failure(error))
      throw error
    }
  }

  private func waitForInFlightFinalize() async throws {
    try await withCheckedThrowingContinuation { continuation in
      let decision = state.withLock { state -> FinalizeWaitDecision in
        if state.finalizing {
          state.finalizeWaiters.append(continuation)
          return .wait
        }
        if let finalizeResult = state.finalizeResult {
          return .replay(finalizeResult)
        }
        return .resumeSuccess
      }

      switch decision {
      case .wait:
        break
      case .replay(let finalizeResult):
        continuation.resume(with: finalizeResult.result)
      case .resumeSuccess:
        continuation.resume()
      }
    }
  }

  private func completeFinalize(with result: Result<Void, Error>) {
    let waiters = state.withLock { state in
      state.finalizeResult = StoredFinalizeResult(result: result)
      state.stopped = true
      state.finalizing = false
      if case .success = result {
        state.finalized = true
      }
      let waiters = state.finalizeWaiters
      state.finalizeWaiters.removeAll()
      return waiters
    }
    for waiter in waiters {
      waiter.resume(with: result)
    }
  }

  func snapshot() -> AudioSourceShutdownSnapshot {
    state.withLock {
      AudioSourceShutdownSnapshot(finalized: $0.finalized, stopped: $0.stopped)
    }
  }

  func injectFinalizeBusErrorForTesting(_ error: GStreamerError) {
    state.withLock { $0.injectedFinalizeError = error }
  }

  private func takeInjectedFinalizeError() -> GStreamerError? {
    state.withLock { state in
      let error = state.injectedFinalizeError
      state.injectedFinalizeError = nil
      return error
    }
  }

  private static func performFinalize(
    pipeline: Pipeline,
    reliableCoordinator: LiveAudioReliablePacketCoordinator?,
    timeout: Duration,
    injectedError: GStreamerError?
  ) async throws {
    do {
      let sendEOS = reliableCoordinator?.sendEOSForFinalize(pipeline: pipeline) ?? pipeline.sendEOS()
      guard sendEOS else {
        throw GStreamerError.busError(
          "Failed to send EOS event",
          source: "AudioSource.finalize",
          debug: nil
        )
      }

      if let injectedError {
        throw injectedError
      }
      if let hookError = reliableCoordinator?.finalizeErrorAfterSendEOSForTesting() {
        throw hookError
      }
      try await waitForEOSOrError(on: pipeline.bus, timeout: timeout)
      reliableCoordinator?.reportEOSFromFinalize()
      if let reliableCoordinator {
        await reliableCoordinator.waitUntilDrainedOrCancelled()
      }
      reliableCoordinator?.markFinalizedFromSource()
      pipeline.stop()
      gst_bus_set_flushing(pipeline.bus._bus, 0)
    } catch {
      reliableCoordinator?.stopFromSource()
      pipeline.stop()
      gst_bus_set_flushing(pipeline.bus._bus, 0)
      throw error
    }
  }

  private static func waitForEOSOrError(on bus: Bus, timeout: Duration) async throws {
    let timeoutNanoseconds = ReliableDurationConversion.nanosecondsClampingNegativeToZero(timeout)

    try await withThrowingTaskGroup(of: Void.self) { group in
      defer { group.cancelAll() }

      group.addTask {
        for await message in bus.messages(filter: [.eos, .error]) {
          switch message {
          case .eos:
            return
          case .error(let message, let debug):
            throw GStreamerError.busError(
              message,
              source: "AudioSource.finalize",
              debug: debug
            )
          default:
            continue
          }
        }
      }

      group.addTask {
        try await Task.sleep(nanoseconds: timeoutNanoseconds)
        throw GStreamerError.busError(
          "Timed out waiting for EOS during live reliable finalization",
          source: "AudioSource.finalize",
          debug: "timeout=\(timeoutNanoseconds)"
        )
      }

      _ = try await group.next()
    }
  }
}

internal final class AudioSourceReliablePacketProbeState: @unchecked Sendable {
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

  func snapshot(
    shutdownState: AudioSourceShutdownSnapshot,
    activePipeline: Pipeline?,
    activeSequence: Bool
  ) -> ReliablePacketRuntimeSnapshotForTesting {
    state.withLock {
      ReliablePacketRuntimeSnapshotForTesting(
        newSampleHandlerCount: $0.newSampleHandlerCount,
        pendingContinuationCount: $0.pendingContinuationCount,
        cleanupAcknowledgementCount: $0.cleanupAcknowledgementCount,
        finalized: shutdownState.finalized,
        stopped: shutdownState.stopped,
        activePipeline: activePipeline,
        activeSequence: activeSequence
      )
    }
  }
}

internal final class LiveAudioReliablePacketCoordinator: @unchecked Sendable {
  private struct State {
    var sequenceClaimed = false
    var sequenceActive = false
    var bridge: LiveAudioReliablePacketBridge?
  }

  private let pipeline: Pipeline
  private let sinkElement: Element
  private let bus: Bus
  private let configuration: AudioSourceReliableDeliveryConfiguration
  private let state = Mutex(State())

  init(
    pipeline: Pipeline,
    sinkName: String,
    configuration: AudioSourceReliableDeliveryConfiguration
  ) throws {
    guard let sinkElement = pipeline.element(named: sinkName) else {
      throw GStreamerError.elementNotFound(sinkName)
    }
    self.pipeline = pipeline
    self.sinkElement = sinkElement
    self.bus = pipeline.bus
    self.configuration = configuration
    let bridge = LiveAudioReliablePacketBridge(
      pipeline: pipeline,
      sinkElement: sinkElement,
      bus: pipeline.bus,
      configuration: configuration,
      onSequenceInactive: { [weak self] in
        self?.markSequenceInactive()
      }
    )
    try bridge.startCallbacks()
    state.withLock { $0.bridge = bridge }
    configuration.probeState.recordPipeline(pipeline)
  }

  func reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>> {
    let bridge = state.withLock { state -> LiveAudioReliablePacketBridge? in
      guard !state.sequenceClaimed else { return nil }
      state.sequenceClaimed = true
      state.sequenceActive = true
      return state.bridge
    }

    guard let bridge else {
      throw GStreamerError.invalidArgument(
        parameter: "AudioSource.reliablePackets",
        reason: "Reliable delivery already has an active sequence"
      )
    }

    return ReliablePackets<ReliablePacket<Buffer>>(
      next: {
        try await bridge.next()
      },
      cancel: {
        bridge.cancel()
      }
    )
  }

  func stopFromSource() {
    let bridge = state.withLock { state in
      state.sequenceActive = false
      return state.bridge
    }
    bridge?.stopFromSource()
    configuration.probeState.clearPipeline(pipeline)
  }

  func reportEOSFromFinalize() {
    state.withLock { $0.bridge }?.reportEOS()
  }

  func waitUntilDrainedOrCancelled() async {
    let bridge = state.withLock { $0.bridge }
    await bridge?.waitUntilDrainedOrCancelled()
  }

  func markFinalizedFromSource() {
    let bridge = state.withLock { state in
      state.sequenceActive = false
      return state.bridge
    }
    bridge?.markFinalizedFromSource()
    configuration.probeState.clearPipeline(pipeline)
  }

  func sendEOSForFinalize(pipeline: Pipeline) -> Bool {
    configuration.sendEOSForTesting?(pipeline) ?? pipeline.sendEOS()
  }

  func finalizeErrorAfterSendEOSForTesting() -> GStreamerError? {
    configuration.finalizeErrorAfterSendEOSForTesting?()
  }

  func runtimeSnapshot(
    shutdownState: AudioSourceShutdownSnapshot
  ) -> ReliablePacketRuntimeSnapshotForTesting {
    let activeSequence = state.withLock { $0.sequenceActive }
    return configuration.probeState.snapshot(
      shutdownState: shutdownState,
      activePipeline: configuration.probeState.pipeline(),
      activeSequence: activeSequence
    )
  }

  func activePipelineForTesting() -> Pipeline? {
    configuration.probeState.pipeline()
  }

  func firstSampleCapsForTesting() async throws -> String {
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
      source: "AudioSource.reliablePackets",
      debug: nil
    )
  }

  func injectBusErrorForTesting(_ error: GStreamerError) {
    state.withLock { $0.bridge }?.reportBusError(error)
  }

  func injectDiscontinuityForTesting(
    kind: Discontinuity.Kind,
    pts: UInt64?,
    duration: UInt64?
  ) {
    state.withLock { $0.bridge }?.storePendingDiscontinuityForTesting(
      kind: kind,
      pts: pts,
      duration: duration
    )
  }

  private func markSequenceInactive() {
    state.withLock { $0.sequenceActive = false }
  }
}

private final class LiveAudioReliablePacketBridge: @unchecked Sendable {
  private final class RetainedCaps: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<GstCaps>

    init(pointer: UnsafeMutablePointer<GstCaps>) {
      self.pointer = pointer
    }

    deinit {
      swift_gst_caps_unref(pointer)
    }
  }

  private struct PacketState {
    var pending: CheckedContinuation<Bool, Error>?
    var drainWaiters: [CheckedContinuation<Void, Never>] = []
    var sampleGeneration: UInt64 = 0
    var eos = false
    var terminalError: Error?
    var cancelled = false
    var stopped = false
    var completed = false
    var nextStarted = false
    var reportedFirstSampleCaps = false
    var priorPTS: UInt64?
    var priorDuration: UInt64?
    var previousCaps: RetainedCaps?
    var pendingDiscontinuity: Discontinuity?
    var discontinuityVersion: UInt64 = 0

    mutating func replacePreviousCaps(with caps: RetainedCaps?) -> RetainedCaps? {
      let oldCaps = previousCaps
      previousCaps = caps
      discontinuityVersion &+= 1
      return oldCaps
    }

    mutating func clearPreviousCaps() -> RetainedCaps? {
      guard previousCaps != nil else {
        return nil
      }
      return replacePreviousCaps(with: nil)
    }

    mutating func storePendingDiscontinuity(_ discontinuity: Discontinuity?) {
      pendingDiscontinuity = discontinuity
      discontinuityVersion &+= 1
    }

    mutating func clearPendingDiscontinuityAndSetPrior(
      pts: UInt64?,
      duration: UInt64?
    ) {
      pendingDiscontinuity = nil
      priorPTS = pts
      priorDuration = duration
      discontinuityVersion &+= 1
    }
  }

  private struct DiscontinuitySnapshot {
    let previousCaps: RetainedCaps?
    let priorPTS: UInt64?
    let priorDuration: UInt64?
    let pendingDiscontinuity: Discontinuity?
    let discontinuityVersion: UInt64
  }

  private enum DiscontinuitySnapshotDecision {
    case closed
    case snapshot(DiscontinuitySnapshot)
  }

  private enum DiscontinuityApplyDecision {
    case closed
    case retry
    case applied(Discontinuity?, oldPreviousCaps: RetainedCaps?)
  }

  private struct CallbackState {
    var cleanedUp = false
    var newSampleDisconnected = false
    var eosDisconnected = false
    var busDisconnected = false

    mutating func markStartupRollbackNewSampleDisconnected(
      eos: Bool = false,
      bus: Bool = false
    ) {
      newSampleDisconnected = true
      if eos {
        eosDisconnected = true
      }
      if bus {
        busDisconnected = true
      }
    }
  }

  private let pipeline: Pipeline
  private let sinkElement: Element
  private let bus: Bus
  private let configuration: AudioSourceReliableDeliveryConfiguration
  private let probeState: AudioSourceReliablePacketProbeState
  private let onSequenceInactive: @Sendable () -> Void
  private let packetState = Mutex(PacketState())
  private let callbackState = Mutex(CallbackState())
  private var newSampleRegistration: OpaquePointer?
  private var eosRegistration: OpaquePointer?
  private var busRegistration: OpaquePointer?

  private var appSink: UnsafeMutablePointer<GstAppSink> {
    UnsafeMutableRawPointer(sinkElement.element).assumingMemoryBound(to: GstAppSink.self)
  }

  init(
    pipeline: Pipeline,
    sinkElement: Element,
    bus: Bus,
    configuration: AudioSourceReliableDeliveryConfiguration,
    onSequenceInactive: @escaping @Sendable () -> Void
  ) {
    self.pipeline = pipeline
    self.sinkElement = sinkElement
    self.bus = bus
    self.configuration = configuration
    self.probeState = configuration.probeState
    self.onSequenceInactive = onSequenceInactive
  }

  func startCallbacks() throws {
    let context = LiveAudioReliableCallbackContext(bridge: self)
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    let appSink = UnsafeMutableRawPointer(sinkElement.element).assumingMemoryBound(to: GstAppSink.self)

    try withExtendedLifetime(context) {
      guard
        let newSampleRegistration = swift_gst_app_sink_connect_new_sample(
          appSink,
          liveAudioReliableNewSampleCallback,
          contextPointer,
          liveAudioReliableRetainContext,
          liveAudioReliableReleaseContext
        )
      else {
        throw GStreamerError.busError(
          "Failed to connect appsink new-sample callback",
          source: "AudioSource.reliablePackets",
          debug: nil
        )
      }
      probeState.incrementNewSampleHandlerCount()

      guard
        let eosRegistration = swift_gst_app_sink_connect_eos(
          appSink,
          liveAudioReliableEOSCallback,
          contextPointer,
          liveAudioReliableRetainContext,
          liveAudioReliableReleaseContext
        )
      else {
        swift_gst_callback_registration_disconnect(newSampleRegistration)
        probeState.decrementNewSampleHandlerCount()
        callbackState.withLock {
          $0.markStartupRollbackNewSampleDisconnected()
        }
        throw GStreamerError.busError(
          "Failed to connect appsink eos callback",
          source: "AudioSource.reliablePackets",
          debug: nil
        )
      }

      guard
        let busRegistration = swift_gst_bus_connect_sync_message_observer(
          bus._bus,
          liveAudioReliableBusSyncMessageCallback,
          contextPointer,
          liveAudioReliableRetainContext,
          liveAudioReliableReleaseContext
        )
      else {
        swift_gst_callback_registration_disconnect(newSampleRegistration)
        probeState.decrementNewSampleHandlerCount()
        swift_gst_callback_registration_disconnect(eosRegistration)
        callbackState.withLock {
          $0.markStartupRollbackNewSampleDisconnected(eos: true)
        }
        throw GStreamerError.busError(
          "Failed to connect bus sync-message observer",
          source: "AudioSource.reliablePackets",
          debug: nil
        )
      }

      self.newSampleRegistration = newSampleRegistration
      self.eosRegistration = eosRegistration
      self.busRegistration = busRegistration
    }
  }

  deinit {
    cancel()
  }

  func next() async throws -> ReliablePacket<Buffer>? {
    try await withTaskCancellationHandler {
      try await nextUntilPacketOrEOS()
    } onCancel: {
      cancel()
    }
  }

  func cancel() {
    let cleanup = packetState.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard !state.cancelled else { return nil }
      state.cancelled = true
      state.completed = true
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        probeState.setPendingContinuationCount(0)
      }
      return pending
    }

    cleanup?.resume(throwing: CancellationError())
    onSequenceInactive()
    notifyDrainWaiters()
    cleanupCallbacks()
    releasePreviousCaps()
  }

  func stopFromSource() {
    let pending = packetState.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard !state.stopped else { return nil }
      state.stopped = true
      state.eos = true
      state.completed = true
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        probeState.setPendingContinuationCount(0)
      }
      return pending
    }

    pending?.resume(returning: false)
    onSequenceInactive()
    notifyDrainWaiters()
    cleanupCallbacks()
    releasePreviousCaps()
  }

  func markFinalizedFromSource() {
    let pending = packetState.withLock { state -> CheckedContinuation<Bool, Error>? in
      state.eos = true
      state.completed = true
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        probeState.setPendingContinuationCount(0)
      }
      return pending
    }

    pending?.resume(returning: false)
    onSequenceInactive()
    notifyDrainWaiters()
    cleanupCallbacks()
    releasePreviousCaps()
  }

  func waitUntilDrainedOrCancelled() async {
    await withCheckedContinuation { continuation in
      let shouldResume = packetState.withLock { state in
        if !state.nextStarted || state.completed || state.cancelled {
          return true
        }
        state.drainWaiters.append(continuation)
        return false
      }

      if shouldResume {
        continuation.resume()
      }
    }
  }

  func reportNewSample() {
    let pending = packetState.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard !state.cancelled, !state.stopped else { return nil }
      state.sampleGeneration &+= 1
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        probeState.setPendingContinuationCount(0)
      }
      return pending
    }
    pending?.resume(returning: true)
  }

  func reportEOS() {
    let pending = packetState.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard !state.cancelled, !state.stopped else { return nil }
      state.eos = true
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        probeState.setPendingContinuationCount(0)
      }
      return pending
    }
    pending?.resume(returning: true)
  }

  func reportEOSFromCallback() {
    guard !configuration.suppressEOSCallbacksForTesting else { return }
    reportEOS()
  }

  func reportBusError(_ error: GStreamerError) {
    let pending = packetState.withLock { state -> CheckedContinuation<Bool, Error>? in
      guard !state.cancelled, !state.stopped else { return nil }
      state.terminalError = error
      let pending = state.pending
      state.pending = nil
      if pending != nil {
        probeState.setPendingContinuationCount(0)
      }
      return pending
    }
    pending?.resume(throwing: error)
  }

  func storePendingDiscontinuityForTesting(
    kind: Discontinuity.Kind,
    pts: UInt64?,
    duration: UInt64?
  ) {
    packetState.withLock { state in
      let discontinuity = Discontinuity(
        kind: kind,
        priorPTS: state.priorPTS,
        priorDuration: state.priorDuration,
        nextPTS: nil,
        duration: nil,
        droppedCount: nil
      )
      state.storePendingDiscontinuity(Self.preferredDiscontinuity(
        state.pendingDiscontinuity,
        discontinuity
      ))
    }
  }

  private func nextUntilPacketOrEOS() async throws -> ReliablePacket<Buffer>? {
    while true {
      try Task.checkCancellation()
      let generation = packetState.withLock { state in
        state.nextStarted = true
        return state.sampleGeneration
      }

      if let packet = try pullPacket() {
        return packet
      }

      if try await waitForEvent(after: generation) == false {
        completeCleanEOS()
        return nil
      }
    }
  }

  private func pullPacket() throws -> ReliablePacket<Buffer>? {
    let shouldPull = packetState.withLock { state in
      !state.cancelled && !state.stopped
    }
    guard shouldPull else {
      return nil
    }

    guard let sample = swift_gst_app_sink_try_pull_sample(appSink, 0) else {
      if swift_gst_app_sink_is_eos(appSink) != 0 {
        reportEOS()
      }
      return nil
    }
    defer { swift_gst_sample_unref(UnsafeMutableRawPointer(sample)) }

    let caps = swift_gst_sample_get_caps(UnsafeMutableRawPointer(sample))
    reportFirstSampleCapsIfNeeded(caps)

    guard let gstBuffer = swift_gst_sample_get_buffer(UnsafeMutableRawPointer(sample)) else {
      throw GStreamerError.bufferMapFailed
    }

    let pts = clockTime(swift_gst_buffer_get_pts(gstBuffer))
    let duration = clockTime(swift_gst_buffer_get_duration(gstBuffer))
    let bufferSize = swift_gst_buffer_get_size(gstBuffer)
    let discontinuity = detectDiscontinuity(
      caps: caps,
      buffer: gstBuffer,
      pts: pts,
      duration: duration,
      isMarker: bufferSize == 0
    )

    if bufferSize == 0 {
      return nil
    }

    _ = swift_gst_buffer_ref(gstBuffer)
    return ReliablePacket(
      payload: Buffer(buffer: gstBuffer, ownsReference: true),
      pts: pts,
      duration: duration,
      priorDiscontinuity: discontinuity
    )
  }

  private func waitForEvent(after generation: UInt64) async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      let immediate = packetState.withLock { state -> Result<Bool, Error>? in
        if state.cancelled {
          return .failure(CancellationError())
        }
        if let terminalError = state.terminalError {
          return .failure(terminalError)
        }
        if state.stopped || state.completed {
          return .success(false)
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
        probeState.setPendingContinuationCount(1)
        return nil
      }

      if let immediate {
        continuation.resume(with: immediate)
      }
    }
  }

  private func completeCleanEOS() {
    packetState.withLock { $0.completed = true }
    onSequenceInactive()
    notifyDrainWaiters()
    cleanupCallbacks()
    releasePreviousCaps()
  }

  private func notifyDrainWaiters() {
    let waiters = packetState.withLock { state in
      let waiters = state.drainWaiters
      state.drainWaiters.removeAll()
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func reportFirstSampleCapsIfNeeded(_ caps: UnsafeMutablePointer<GstCaps>?) {
    guard let caps else { return }
    let shouldReport = packetState.withLock { state in
      guard !state.reportedFirstSampleCaps else {
        return false
      }
      state.reportedFirstSampleCaps = true
      return true
    }

    guard shouldReport,
      let capsString = GLibString.takeOwnership(swift_gst_caps_to_string(caps))
    else {
      return
    }
    probeState.recordFirstSampleCaps(capsString)
    configuration.firstSampleCapsProbe?(capsString)
  }

  private func detectDiscontinuity(
    caps: UnsafeMutablePointer<GstCaps>?,
    buffer: UnsafeMutablePointer<GstBuffer>,
    pts: UInt64?,
    duration: UInt64?,
    isMarker: Bool
  ) -> Discontinuity? {
    let hasDiscont = swift_gst_buffer_has_discont_flag(buffer) != 0
    let hasGap = swift_gst_buffer_has_gap_flag(buffer) != 0

    while true {
      let snapshotDecision = packetState.withLock { state -> DiscontinuitySnapshotDecision in
        guard !state.cancelled, !state.stopped, !state.completed else {
          return .closed
        }
        return .snapshot(
          DiscontinuitySnapshot(
            previousCaps: state.previousCaps,
            priorPTS: state.priorPTS,
            priorDuration: state.priorDuration,
            pendingDiscontinuity: state.pendingDiscontinuity,
            discontinuityVersion: state.discontinuityVersion
          )
        )
      }

      let snapshot: DiscontinuitySnapshot
      switch snapshotDecision {
      case .closed:
        return nil
      case .snapshot(let value):
        snapshot = value
      }

      let priorPTS = snapshot.priorPTS
      let priorDuration = snapshot.priorDuration
      let formatChanged: Bool
      let nextPreviousCaps: RetainedCaps?
      if let caps {
        if let previousCaps = snapshot.previousCaps {
          if swift_gst_caps_is_equal(previousCaps.pointer, caps) == 0,
            let retainedCaps = swift_gst_caps_ref(caps)
          {
            nextPreviousCaps = RetainedCaps(pointer: retainedCaps)
            formatChanged = true
          } else {
            nextPreviousCaps = nil
            formatChanged = false
          }
        } else if let retainedCaps = swift_gst_caps_ref(caps) {
          nextPreviousCaps = RetainedCaps(pointer: retainedCaps)
          formatChanged = false
        } else {
          nextPreviousCaps = nil
          formatChanged = false
        }
      } else {
        nextPreviousCaps = nil
        formatChanged = false
      }

      let gapDuration = Self.gapDuration(
        priorPTS: priorPTS,
        priorDuration: priorDuration,
        nextPTS: pts
      )
      let inferredDrop = (gapDuration ?? 0) > 0
      let discontSignal = hasDiscont

      let kind: Discontinuity.Kind?
      if formatChanged {
        kind = .formatChange
      } else if discontSignal {
        kind = .discont
      } else if hasGap {
        kind = .gap
      } else if inferredDrop {
        kind = .dropped
      } else {
        kind = nil
      }

      let selectedDiscontinuity: Discontinuity?
      if isMarker {
        if let kind {
          let marker = Discontinuity(
            kind: kind,
            priorPTS: priorPTS,
            priorDuration: priorDuration,
            nextPTS: nil,
            duration: nil,
            droppedCount: nil
          )
          selectedDiscontinuity = Self.preferredDiscontinuity(
            snapshot.pendingDiscontinuity,
            marker
          )
        } else {
          selectedDiscontinuity = snapshot.pendingDiscontinuity
        }
      } else {
        let currentDiscontinuity = kind.map {
          Discontinuity(
            kind: $0,
            priorPTS: priorPTS,
            priorDuration: priorDuration,
            nextPTS: pts,
            duration: gapDuration,
            droppedCount: nil
          )
        }
        selectedDiscontinuity = Self.preferredDiscontinuity(
          snapshot.pendingDiscontinuity,
          currentDiscontinuity
        ).map { selected in
          Discontinuity(
            kind: selected.kind,
            priorPTS: selected.priorPTS,
            priorDuration: selected.priorDuration,
            nextPTS: pts,
            duration: Self.gapDuration(
              priorPTS: selected.priorPTS,
              priorDuration: selected.priorDuration,
              nextPTS: pts
            ),
            droppedCount: nil
          )
        }
      }

      let applyDecision = packetState.withLock { state -> DiscontinuityApplyDecision in
        guard !state.cancelled, !state.stopped, !state.completed else {
          return .closed
        }
        let stateversion = state.discontinuityVersion
        let snapshotversion = snapshot.discontinuityVersion
        guard stateversion == snapshotversion else {
          return .retry
        }

        let oldPreviousCaps: RetainedCaps?
        if let nextPreviousCaps {
          oldPreviousCaps = state.replacePreviousCaps(with: nextPreviousCaps)
        } else {
          oldPreviousCaps = nil
        }

        if isMarker {
          state.storePendingDiscontinuity(selectedDiscontinuity)
          return .applied(nil, oldPreviousCaps: oldPreviousCaps)
        }

        state.clearPendingDiscontinuityAndSetPrior(pts: pts, duration: duration)
        return .applied(selectedDiscontinuity, oldPreviousCaps: oldPreviousCaps)
      }

      switch applyDecision {
      case .closed:
        return nil
      case .retry:
        continue
      case .applied(let discontinuity, let oldPreviousCaps):
        if let oldPreviousCaps {
          withExtendedLifetime(oldPreviousCaps) {}
        }
        return discontinuity
      }
    }
  }

  private func releasePreviousCaps() {
    let caps = packetState.withLock { state -> RetainedCaps? in
      state.clearPreviousCaps()
    }
    if let caps {
      withExtendedLifetime(caps) {}
    }
  }

  private func cleanupCallbacks() {
    let disconnects = callbackState.withLock { state in
      guard !state.cleanedUp else {
        return (newSample: false, eos: false, bus: false)
      }
      state.cleanedUp = true
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

    probeState.clearPipeline(pipeline)
    probeState.setPendingContinuationCount(0)
    probeState.acknowledgeCleanup()
    configuration.onCleanupForTesting?()
  }

  private func clockTime(_ value: GstClockTime) -> UInt64? {
    swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
  }

  private static func gapDuration(
    priorPTS: UInt64?,
    priorDuration: UInt64?,
    nextPTS: UInt64?
  ) -> UInt64? {
    guard let priorPTS, let priorDuration, let nextPTS else {
      return nil
    }
    let end = priorPTS.addingReportingOverflow(priorDuration)
    guard !end.overflow, nextPTS >= end.partialValue else {
      return nil
    }
    return nextPTS - end.partialValue
  }

  private static func preferredDiscontinuity(
    _ first: Discontinuity?,
    _ second: Discontinuity?
  ) -> Discontinuity? {
    guard let first else { return second }
    guard let second else { return first }
    return precedence(first.kind) <= precedence(second.kind) ? first : second
  }

  private static func precedence(_ kind: Discontinuity.Kind) -> Int {
    switch kind {
    case .formatChange: return 0
    case .discont: return 1
    case .gap: return 2
    case .dropped: return 3
    }
  }
}

internal extension Buffer {
  mutating func setReliableLiveGapFlagForTesting() {
    swift_gst_buffer_set_flags(buffer, swift_gst_buffer_flag_gap())
  }

  mutating func setReliableLiveDiscontFlagForTesting() {
    swift_gst_buffer_set_flags(buffer, swift_gst_buffer_flag_discont())
  }
}

private final class LiveAudioReliableCallbackContext: @unchecked Sendable {
  let bridge: LiveAudioReliablePacketBridge

  init(bridge: LiveAudioReliablePacketBridge) {
    self.bridge = bridge
  }
}

private func liveAudioReliableRetainContext(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  _ = Unmanaged<LiveAudioReliableCallbackContext>.fromOpaque(context).retain()
}

private func liveAudioReliableReleaseContext(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<LiveAudioReliableCallbackContext>.fromOpaque(context).release()
}

private func liveAudioReliableNewSampleCallback(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  let callbackContext = Unmanaged<LiveAudioReliableCallbackContext>
    .fromOpaque(context)
    .takeUnretainedValue()
  callbackContext.bridge.reportNewSample()
}

private func liveAudioReliableEOSCallback(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  let callbackContext = Unmanaged<LiveAudioReliableCallbackContext>
    .fromOpaque(context)
    .takeUnretainedValue()
  callbackContext.bridge.reportEOSFromCallback()
}

private func liveAudioReliableBusSyncMessageCallback(
  _ message: UnsafeMutablePointer<GstMessage>?,
  _ context: UnsafeMutableRawPointer?
) {
  guard let message, let context else {
    return
  }

  let callbackContext = Unmanaged<LiveAudioReliableCallbackContext>
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
    callbackContext.bridge.reportBusError(error)

  case GST_MESSAGE_EOS:
    callbackContext.bridge.reportEOSFromCallback()

  default:
    break
  }
}
