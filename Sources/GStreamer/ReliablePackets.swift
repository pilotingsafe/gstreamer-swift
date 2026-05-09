import Synchronization

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
