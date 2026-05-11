import Synchronization

/// A live reliable packet and its boundary metadata.
///
/// `ReliablePacket` is used for encoded live audio reliable delivery. The
/// payload carries the encoded data, while the timestamp fields mirror
/// ``Buffer/pts`` and ``Buffer/duration`` in nanoseconds.
public struct ReliablePacket<Payload: Sendable>: Sendable {
  /// The packet payload.
  public let payload: Payload

  /// The packet presentation timestamp in nanoseconds, if present.
  public let pts: UInt64?

  /// The packet duration in nanoseconds, if present.
  public let duration: UInt64?

  /// A discontinuity observed immediately before this packet, if any.
  public let priorDiscontinuity: Discontinuity?

  /// Create a reliable packet value.
  public init(
    payload: Payload,
    pts: UInt64?,
    duration: UInt64?,
    priorDiscontinuity: Discontinuity?
  ) {
    self.payload = payload
    self.pts = pts
    self.duration = duration
    self.priorDiscontinuity = priorDiscontinuity
  }
}

/// A discontinuity observed at a live reliable packet boundary.
///
/// Version 1 surfaces at most one discontinuity per packet using precedence:
/// ``Kind/formatChange``, ``Kind/discont``, ``Kind/gap``, then
/// ``Kind/dropped``. ``duration`` is the gap duration only, calculated as
/// `nextPTS - (priorPTS + priorDuration)` when all values are available.
public struct Discontinuity: Sendable {
  /// The reason this packet boundary is discontinuous.
  public enum Kind: Sendable, Equatable {
    /// The sample caps changed according to GStreamer's structured caps equality.
    case formatChange

    /// The current buffer has GStreamer's DISCONT flag.
    case discont

    /// The current buffer has GStreamer's GAP flag.
    case gap

    /// Packet timing implies at least one dropped interval.
    case dropped
  }

  /// The discontinuity kind.
  public let kind: Kind

  /// The previous packet PTS in nanoseconds, if known.
  public let priorPTS: UInt64?

  /// The previous packet duration in nanoseconds, if known.
  public let priorDuration: UInt64?

  /// The current packet PTS in nanoseconds, if known.
  public let nextPTS: UInt64?

  /// Gap duration only, not including the previous packet duration.
  public let duration: UInt64?

  /// Reserved for future inference. Version 1 always reports `nil`.
  public let droppedCount: Int?

  /// Create a discontinuity value.
  public init(
    kind: Kind,
    priorPTS: UInt64?,
    priorDuration: UInt64?,
    nextPTS: UInt64?,
    duration: UInt64?,
    droppedCount: Int?
  ) {
    self.kind = kind
    self.priorPTS = priorPTS
    self.priorDuration = priorDuration
    self.nextPTS = nextPTS
    self.duration = duration
    self.droppedCount = droppedCount
  }
}

/// A single-consumer async sequence for no-drop packet delivery.
///
/// `ReliablePackets` is intended for finite or otherwise backpressureable
/// sources. Unlike realtime `packets()` streams, it pulls one element only when
/// the consumer awaits `next()`, and surfaces pipeline failures by throwing.
///
/// Each `ReliablePackets` value supports one active iterator. Creating or using
/// another iterator for the same sequence is rejected at runtime.
public struct ReliablePackets<Element: Sendable>: AsyncSequence, Sendable {
  private let storage: Storage

  internal init(
    next: @escaping @Sendable () async throws -> Element?,
    cancel: @escaping @Sendable () -> Void
  ) {
    self.storage = Storage(next: next, cancel: cancel)
  }

  /// Creates the sequence's single supported iterator.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(storage: storage)
  }

  /// The single-consumer iterator for `ReliablePackets`.
  public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
    private let core: IteratorCore

    fileprivate init(storage: Storage) {
      self.core = IteratorCore(storage: storage)
    }

    /// Returns the next element, throws on pipeline failure, or returns `nil`
    /// after clean end-of-stream.
    @concurrent
    public func next() async throws -> Element? {
      try await core.next()
    }
  }

  fileprivate final class Storage: @unchecked Sendable {
    private struct State: Sendable {
      var iteratorClaimed = false
      var completed = false
    }

    private let state = Mutex(State())
    private let producerNext: @Sendable () async throws -> Element?
    private let producerCancel: @Sendable () -> Void

    init(
      next: @escaping @Sendable () async throws -> Element?,
      cancel: @escaping @Sendable () -> Void
    ) {
      self.producerNext = next
      self.producerCancel = cancel
    }

    func claimIterator() -> Bool {
      state.withLock { state in
        guard !state.iteratorClaimed else { return false }
        state.iteratorClaimed = true
        return true
      }
    }

    func isCompleted() -> Bool {
      state.withLock { $0.completed }
    }

    func markCompleted() {
      state.withLock { $0.completed = true }
    }

    func nextElement() async throws -> Element? {
      try await producerNext()
    }

    func cancel() {
      producerCancel()
    }
  }

  private final class IteratorCore: @unchecked Sendable {
    private struct State: Sendable {
      var started = false
      var firstNextCompleted = false
      var nextInFlight = false
      var finished = false
    }

    private let storage: Storage
    private let state = Mutex(State())

    init(storage: Storage) {
      self.storage = storage
    }

    deinit {
      let shouldCancel = state.withLock { state in
        state.started && !state.finished
      }
      if shouldCancel {
        storage.cancel()
      }
    }

    func next() async throws -> Element? {
      let shouldCallProducer = try beginNext()
      guard shouldCallProducer else {
        return nil
      }

      do {
        let element = try await withTaskCancellationHandler {
          try await storage.nextElement()
        } onCancel: {
          storage.cancel()
        }

        endNext(finished: element == nil)
        if element == nil {
          storage.markCompleted()
        }
        return element
      } catch {
        endNext(finished: true)
        storage.markCompleted()
        storage.cancel()
        throw error
      }
    }

    private func beginNext() throws -> Bool {
      try state.withLock { state in
        if state.finished {
          state.finished = true
          return false
        }

        if storage.isCompleted() {
          if state.started {
            state.finished = true
            return false
          }
          throw GStreamerError.invalidArgument(
            parameter: "ReliablePackets",
            reason: "ReliablePackets supports a single active iterator"
          )
        }

        if state.nextInFlight {
          if state.firstNextCompleted {
            throw GStreamerError.invalidArgument(
              parameter: "ReliablePackets.AsyncIterator",
              reason: "Concurrent next() calls are unsupported"
            )
          }
          throw GStreamerError.invalidArgument(
            parameter: "ReliablePackets",
            reason: "ReliablePackets supports a single active iterator"
          )
        }

        if !state.started {
          guard storage.claimIterator() else {
            throw GStreamerError.invalidArgument(
              parameter: "ReliablePackets",
              reason: "ReliablePackets supports a single active iterator"
            )
          }
          state.started = true
        }

        state.nextInFlight = true
        return true
      }
    }

    private func endNext(finished: Bool) {
      state.withLock { state in
        state.nextInFlight = false
        state.firstNextCompleted = true
        if finished {
          state.finished = true
        }
      }
    }
  }
}

internal enum ReliableDurationConversion {
  static func validateNonNegative(_ duration: Duration) -> Bool {
    duration >= .zero
  }

  static func nanosecondsClampingNegativeToZero(_ duration: Duration) -> UInt64 {
    guard duration > .zero else { return 0 }

    let components = duration.components
    let seconds = components.seconds > 0 ? UInt64(components.seconds) : 0
    let attoseconds = components.attoseconds > 0 ? UInt64(components.attoseconds) : 0
    let fractionalNanoseconds = attoseconds / 1_000_000_000

    let secondsNanoseconds = seconds.multipliedReportingOverflow(by: 1_000_000_000)
    guard !secondsNanoseconds.overflow else { return .max }

    let total = secondsNanoseconds.partialValue.addingReportingOverflow(fractionalNanoseconds)
    return total.overflow ? .max : total.partialValue
  }
}
