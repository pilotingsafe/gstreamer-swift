import Synchronization
@testable import GStreamer

internal struct ReliableLiveDeliveryConfigurationForTesting: Sendable {
  let leaky: QueueLeaky
  let maxBuffers: UInt?
  let maxBytes: UInt?
  let maxTime: Duration?
  let suppressEOSCallbacksForTesting: Bool = false
}

internal enum ReliableLiveFinalizeBehaviorForTesting: Sendable {
  case emitEOSOnSendEOS
  case emitBusErrorOnSendEOS(message: String, source: String?, debug: String?)
  case ignoreSendEOS
  case failSendEOS
}

internal enum ReliableLiveAudioSourceEventForTesting: Sendable {
  case packet(Buffer)
  case gap(pts: UInt64, duration: UInt64)
  case discont
  case formatChange
  case eos
  case busError(message: String, source: String?, debug: String?)
}

internal struct ReliableLiveAudioSourceSnapshotForTesting: Sendable {
  let newSampleHandlerCount: Int
  let pendingContinuationCount: Int
  let cleanupAcknowledgementCount: Int
  let activeSequenceID: Int?
  let sentEOSCount: Int
  let stopCount: Int
}

internal final class ReliableLiveAudioSourceHarnessForTesting: @unchecked Sendable {
  let source: AudioSource

  private let appSource: AppSource
  private let state: ReliableLiveAudioSourceHarnessState

  init(
    encoding: AudioSource.Encoding,
    delivery: ReliableLiveDeliveryConfigurationForTesting,
    finalizeBehavior: ReliableLiveFinalizeBehaviorForTesting,
    suppressEOSCallbacksForTesting: Bool = false,
    appSinkMaxBuffers: UInt = 1
  ) throws {
    let state = ReliableLiveAudioSourceHarnessState(finalizeBehavior: finalizeBehavior)
    let suppressEOSCallbacks =
      delivery.suppressEOSCallbacksForTesting || suppressEOSCallbacksForTesting
    let sourceName = "reliable_live_test_src"
    let sinkName = "reliable_live_test_sink"
    let pipelineDescription = [
      "appsrc name=\(sourceName) is-live=true format=time do-timestamp=false",
      "appsink name=\(sinkName) drop=false sync=false emit-signals=true enable-last-sample=false wait-on-eos=true max-buffers=\(appSinkMaxBuffers)",
    ].joined(separator: " ! ")

    let source = try AudioSource.microphone()
      .withEncoding(encoding)
      .withReliableDelivery(
        leaky: delivery.leaky,
        maxBuffers: delivery.maxBuffers,
        maxBytes: delivery.maxBytes,
        maxTime: delivery.maxTime
      )
      .withReliableDeliveryCandidateDescriptionsForTesting(
        [pipelineDescription],
        sinkName: sinkName,
        queueName: "reliable_delivery_queue"
      )
      .withReliableDeliverySendEOSForTesting { _ in
        state.handleSendEOS()
      }
      .withReliableDeliveryFinalizeErrorForTesting {
        state.takeFinalizeError()
      }
      .withReliableDeliverySuppressEOSCallbacksForTesting(
        suppressEOSCallbacks
      )
      .build()

    guard let pipeline = source.reliablePacketPipelineForTesting() else {
      throw GStreamerError.busError(
        "Reliable live test harness pipeline was not available",
        source: "ReliableLiveAudioSourceHarnessForTesting",
        debug: nil
      )
    }

    let appSource = try AppSource(pipeline: pipeline, name: sourceName)
    appSource.setLive(true)
    appSource.setStreamType(.stream)
    appSource.setMaxBytes(0)
    appSource.setCaps(state.currentCaps())
    state.setAppSource(appSource)

    self.source = source
    self.appSource = appSource
    self.state = state
  }

  func emit(_ event: ReliableLiveAudioSourceEventForTesting) async throws {
    switch event {
    case .packet(let buffer):
      try appSource.push(buffer: buffer)

    case .gap(let pts, let duration):
      source.injectReliableDiscontinuityForTesting(
        kind: .gap,
        pts: pts,
        duration: duration
      )

    case .discont:
      source.injectReliableDiscontinuityForTesting(kind: .discont)

    case .formatChange:
      appSource.setCaps(state.rotateCaps())
      source.injectReliableDiscontinuityForTesting(kind: .formatChange)

    case .eos:
      appSource.endOfStream()

    case .busError(let message, let sourceName, let debug):
      source.injectReliablePacketBusErrorForTesting(
        message: message,
        source: sourceName,
        debug: debug
      )
    }
  }

  func snapshot() async -> ReliableLiveAudioSourceSnapshotForTesting {
    let runtime = source.reliablePacketRuntimeSnapshotForTesting()
    let harness = state.snapshot()
    return ReliableLiveAudioSourceSnapshotForTesting(
      newSampleHandlerCount: runtime.newSampleHandlerCount,
      pendingContinuationCount: runtime.pendingContinuationCount,
      cleanupAcknowledgementCount: runtime.cleanupAcknowledgementCount,
      activeSequenceID: runtime.activeSequence ? 1 : nil,
      sentEOSCount: harness.sentEOSCount,
      stopCount: runtime.stopped ? max(1, harness.stopCount) : harness.stopCount
    )
  }
}

private struct ReliableLiveAudioSourceHarnessStateSnapshot: Sendable {
  let sentEOSCount: Int
  let stopCount: Int
}

private final class ReliableLiveAudioSourceHarnessState: @unchecked Sendable {
  private struct State {
    var appSource: AppSource?
    var finalizeBehavior: ReliableLiveFinalizeBehaviorForTesting
    var pendingFinalizeError: GStreamerError?
    var sentEOSCount = 0
    var stopCount = 0
    var capsIndex = 0
  }

  private let state: Mutex<State>

  init(finalizeBehavior: ReliableLiveFinalizeBehaviorForTesting) {
    self.state = Mutex(State(finalizeBehavior: finalizeBehavior))
  }

  func setAppSource(_ appSource: AppSource) {
    state.withLock { $0.appSource = appSource }
  }

  func currentCaps() -> String {
    state.withLock { Self.caps(index: $0.capsIndex) }
  }

  func rotateCaps() -> String {
    state.withLock { state in
      state.capsIndex += 1
      return Self.caps(index: state.capsIndex)
    }
  }

  func handleSendEOS() -> Bool {
    state.withLock { state in
      state.sentEOSCount += 1
      switch state.finalizeBehavior {
      case .emitEOSOnSendEOS:
        state.appSource?.endOfStream()
        return true

      case .emitBusErrorOnSendEOS(let message, let source, let debug):
        state.pendingFinalizeError = GStreamerError.busError(
          message,
          source: source,
          debug: debug
        )
        return true

      case .ignoreSendEOS:
        return true

      case .failSendEOS:
        return false
      }
    }
  }

  func takeFinalizeError() -> GStreamerError? {
    state.withLock { state in
      let error = state.pendingFinalizeError
      state.pendingFinalizeError = nil
      return error
    }
  }

  func snapshot() -> ReliableLiveAudioSourceHarnessStateSnapshot {
    state.withLock {
      ReliableLiveAudioSourceHarnessStateSnapshot(
        sentEOSCount: $0.sentEOSCount,
        stopCount: $0.stopCount
      )
    }
  }

  private static func caps(index: Int) -> String {
    "application/x-reliable-live-test,variant=(int)\(index)"
  }
}
