import Foundation
import Testing

@Suite("API Safety Static Tests")
struct APISafetyStaticTests {

    @Test("VideoFrame exposes only retained read-only byte access")
    func videoFrameMutableAPIDeclarationsAreRemoved() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/VideoFrame.swift"))
        let mutablePropertyDeclaration = "public var " + "mutableBytes"
        let mutablePointerDeclaration = "public func " + "withUnsafeMutableBytes"

        #expect(!source.contains(mutablePropertyDeclaration))
        #expect(!source.contains(mutablePointerDeclaration))
    }

    @Test("Docs and samples do not reference stale VideoFrame byte access")
    func staleVideoFrameByteAccessReferencesAreRemoved() throws {
        let root = try Self.packageRoot()
        let files = try Self.videoFrameReferenceScanFiles(in: root)
        let stalePatterns = Self.staleVideoFrameReferencePatterns()
        var violations: [String] = []

        for file in files {
            let fileContents = try Self.contents(of: file)
            for pattern in stalePatterns where fileContents.contains(pattern) {
                violations.append("\(Self.relativePath(file, to: root)): \(pattern)")
            }
        }

        #expect(
            violations.isEmpty,
            "Remove stale VideoFrame byte access references:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Video frame documentation explains mutable migration path")
    func workingWithVideoFramesDocumentsMutableMigrationPath() throws {
        let root = try Self.packageRoot()
        let documentation = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/Documentation.docc/WorkingWithVideoFrames.md")
        )

        #expect(Self.containsMutableMigrationGuidance(documentation))
    }

    @Test("Buffer mutable span delegates uniqueness to shared helper")
    func bufferMutableSpanUsesEnsureUniqueWithoutDirectStorageCopy() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Buffer.swift"))
        let implementation = try Self.bracedDeclaration(
            beginningWith: "public var " + "mutableBytes: MutableRawSpan",
            in: source
        )

        #expect(implementation.contains("guard ensureUnique() else"))
        #expect(!implementation.contains("storage.copy()"))
    }

    @Test("Realtime media streams use bounded backpressure policies")
    func realtimeMediaStreamsUseBoundedBackpressurePolicies() throws {
        let root = try Self.packageRoot()
        let audioBufferSinkSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioBufferSink.swift")
        )
        let audioSourceSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift")
        )
        let rawBuffersImplementation = try Self.bracedDeclaration(
            beginningWith: "public func buffers() -> AsyncStream<AudioBuffer>",
            in: audioBufferSinkSource
        )
        let audioPacketSinkSource = try Self.bracedDeclaration(
            beginningWith: "private final class AudioPacketSink",
            in: audioSourceSource
        )
        let encodedPacketsImplementation = try Self.bracedDeclaration(
            beginningWith: "func packets() -> AsyncStream<Buffer>",
            in: audioPacketSinkSource
        )

        #expect(
            Self.containsBufferingNewestPolicy(
                source: audioBufferSinkSource,
                implementation: rawBuffersImplementation,
                expectedCount: 1
            ),
            "AudioBufferSink.buffers() should use .bufferingNewest(1) or a named constant with value 1"
        )
        #expect(
            Self.containsBufferingNewestPolicy(
                source: audioSourceSource,
                implementation: encodedPacketsImplementation,
                expectedCount: 8
            ),
            "AudioPacketSink.packets() should use .bufferingNewest(8) or a named constant with value 8"
        )
    }

    @Test("Public stream return types remain source-compatible")
    func publicStreamReturnTypesRemainSourceCompatible() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let audioBufferSink = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioBufferSink.swift"))
        let bus = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let appSink = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AppSink.swift"))

        #expect(audioSource.contains("public func buffers() -> AsyncStream<AudioBuffer>"))
        #expect(audioSource.contains("public func packets() -> AsyncStream<Buffer>"))
        #expect(audioBufferSink.contains("public func buffers() -> AsyncStream<AudioBuffer>"))
        #expect(bus.contains("public func messages(filter: Filter = [.error, .eos, .stateChanged]) -> AsyncStream<BusMessage>"))
        #expect(bus.contains("public func errors() -> AsyncStream<(message: String, debug: String?)>"))
        #expect(bus.contains("public func warnings() -> AsyncStream<(message: String, debug: String?)>"))
        #expect(bus.contains("public func stateChanges() -> AsyncStream<(old: Pipeline.State, new: Pipeline.State)>"))
        #expect(bus.contains("public func waitForEOSOrError() async throws"))
        #expect(bus.contains("public func waitForEOS() async"))
        #expect(
            bus.range(of: #"public\s+func\s+parseMessage\b"#, options: .regularExpression) == nil,
            "Bus message parsing must not become a public API"
        )
        #expect(appSink.contains("public func frames() -> Frames"))
    }

    @Test("Bus EOS wait convenience APIs preserve compatibility and error handling")
    func busEOSWaitConvenienceAPIsPreserveCompatibilityAndErrorHandling() throws {
        let root = try Self.packageRoot()
        let bus = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let busType = try Self.bracedDeclaration(beginningWith: "public final class Bus", in: bus)
        let waitForEOSOrError = try Self.bracedDeclaration(
            beginningWith: "public func waitForEOSOrError()",
            in: busType
        )
        let waitForEOS = try Self.bracedDeclaration(
            beginningWith: "public func waitForEOS()",
            in: busType
        )
        let waitForEOSOrErrorSignature = Self.normalizedWhitespace(Self.declarationSignature(waitForEOSOrError))
        let waitForEOSSignature = Self.normalizedWhitespace(Self.declarationSignature(waitForEOS))

        #expect(waitForEOSOrErrorSignature.contains("public func waitForEOSOrError() async throws"))
        #expect(waitForEOSSignature.contains("public func waitForEOS() async"))
        #expect(
            Self.containsWaitForEOSDeprecationMarker(in: busType),
            "waitForEOS() must be deprecated with a message mentioning waitForEOSOrError()"
        )
        #expect(
            Self.waitForEOSDelegatesToThrowingHelperAndSwallowsErrors(waitForEOS),
            "Deprecated waitForEOS() must delegate to waitForEOSOrError() and swallow the error"
        )
    }

    @Test("Bus message pull sequence public API is additive and Sendable")
    func busMessagePullSequencePublicAPIIsAdditiveAndSendable() throws {
        let root = try Self.packageRoot()
        let bus = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let busType = try Self.bracedDeclaration(beginningWith: "public final class Bus", in: bus)
        let messages = try Self.bracedDeclaration(beginningWith: "public struct Messages", in: busType)
        let iterator = try Self.bracedDeclaration(beginningWith: "public struct AsyncIterator", in: messages)
        let messagesSignature = Self.normalizedWhitespace(Self.declarationSignature(messages))
        let iteratorSignature = Self.normalizedWhitespace(Self.declarationSignature(iterator))

        #expect(messagesSignature.contains("public struct Messages"))
        #expect(messagesSignature.contains("AsyncSequence"))
        #expect(messagesSignature.contains("Sendable"))
        #expect(
            messages.range(
                of: #"public\s+typealias\s+Element\s*=\s*BusMessage\b"#,
                options: .regularExpression
            ) != nil,
            "Bus.Messages.Element must be BusMessage"
        )
        #expect(iteratorSignature.contains("public struct AsyncIterator"))
        #expect(iteratorSignature.contains("AsyncIteratorProtocol"))
        #expect(iteratorSignature.contains("Sendable"))
        #expect(
            messages.range(
                of: #"public\s+func\s+makeAsyncIterator\(\)\s*->\s*AsyncIterator\b"#,
                options: .regularExpression
            ) != nil,
            "Bus.Messages must expose public makeAsyncIterator() -> AsyncIterator"
        )
        #expect(
            busType.range(
                of: #"public\s+func\s+messageSequence\(\s*filter:\s*Filter\s*=\s*\.all\s*\)\s*->\s*Messages\b"#,
                options: .regularExpression
            ) != nil,
            "Bus must expose public messageSequence(filter: Filter = .all) -> Messages"
        )
        #expect(
            Self.containsBusMessagesNextSignature(in: iterator),
            "Bus.Messages.AsyncIterator.next() must be @concurrent/equivalent and async -> BusMessage? without throws"
        )
    }

    @Test("Bus.Filter public static filters remain source-compatible")
    func busFilterPublicStaticFiltersRemainSourceCompatible() throws {
        let root = try Self.packageRoot()
        let bus = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let filter = try Self.bracedDeclaration(beginningWith: "public struct Filter", in: bus)
        let expectedNames: Set<String> = [
            "error",
            "warning",
            "eos",
            "stateChanged",
            "element",
            "buffering",
            "durationChanged",
            "latency",
            "tag",
            "qos",
            "streamStart",
            "clockLost",
            "newClock",
            "progress",
            "info",
            "all",
        ]
        let exactDeclarations = [
            "public static let error = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_ERROR.rawValue))",
            "public static let warning = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_WARNING.rawValue))",
            "public static let eos = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_EOS.rawValue))",
            "public static let stateChanged = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_STATE_CHANGED.rawValue))",
            "public static let element = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_ELEMENT.rawValue))",
            "public static let buffering = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_BUFFERING.rawValue))",
            "public static let durationChanged = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_DURATION_CHANGED.rawValue))",
            "public static let latency = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_LATENCY.rawValue))",
            "public static let tag = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_TAG.rawValue))",
            "public static let qos = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_QOS.rawValue))",
            "public static let streamStart = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_STREAM_START.rawValue))",
            "public static let clockLost = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_CLOCK_LOST.rawValue))",
            "public static let newClock = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_NEW_CLOCK.rawValue))",
            "public static let progress = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_PROGRESS.rawValue))",
            "public static let info = Filter(rawValue: UInt32(bitPattern: GST_MESSAGE_INFO.rawValue))",
        ]
        let actualNames = Self.publicStaticMemberNames(in: filter)
        let missing = expectedNames.subtracting(actualNames).sorted()
        let unexpected = actualNames.subtracting(expectedNames).sorted()

        for declaration in exactDeclarations {
            #expect(filter.contains(declaration), "Bus.Filter declaration changed: \(declaration)")
        }
        #expect(
            missing.isEmpty && unexpected.isEmpty,
            "Bus.Filter public static filters must be exactly ADR-002's allowed set; missing=\(missing), unexpected=\(unexpected)"
        )
        #expect(
            Self.containsExistingAllFilterDeclaration(in: filter),
            "Bus.Filter.all must remain the existing Swift-modeled aggregate filter"
        )
    }

    @Test("Bus message sequence uses watch-backed queueing without blocking timed pops")
    func busMessageSequenceUsesWatchBackedQueueingWithoutBlockingTimedPops() throws {
        let root = try Self.packageRoot()
        let bus = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let shimHeader = try Self.contents(
            of: root.appendingPathComponent("Sources/CGStreamerShim/include/GStreamerShim.h")
        )
        let shimSource = try Self.contents(
            of: root.appendingPathComponent("Sources/CGStreamerShim/GStreamerShim.c")
        )
        let messageSequenceDocs = try [
            "README.md",
            "CHANGELOG.md",
            "docs/ADRs/ADR-002-bus-message-delivery-model.md",
            "tasks/prd-bus-message-delivery-model.md",
        ].map { path in
            try Self.contents(of: root.appendingPathComponent(path))
        }.joined(separator: "\n")
        let messages = try Self.bracedDeclaration(beginningWith: "public struct Messages", in: bus)
        let messagePump = (try? Self.bracedDeclaration(beginningWith: "fileprivate final class MessagePump", in: bus))
            ?? (try? Self.bracedDeclaration(beginningWith: "private final class MessagePump", in: bus))
            ?? ""
        let enqueue = try Self.bracedDeclaration(beginningWith: "private func enqueue", in: messagePump)
        let sequencePath = [messages, messagePump].joined(separator: "\n")
        let disallowedSnippets = [
            "swift_gst_bus_timed_pop_filtered",
            "100_000_000",
            "swift_gst_message_unref",
            "Task.detached",
            ".bufferingNewest",
            ".bufferingOldest",
        ]
        let violations = disallowedSnippets.filter { sequencePath.contains($0) }

        #expect(
            violations.isEmpty,
            "Bus.Messages must use a watch-backed queue, not blocking timed pops or detached polling:\n\(violations.joined(separator: "\n"))"
        )
        #expect(
            bus.contains("swift_gst_bus_watch"),
            "Bus.Messages must call the private C bus watch shim path"
        )
        #expect(
            Self.containsWatchBackedContinuationQueue(in: bus),
            "Bus message watch pump must use continuations, waiters, and FIFO queueing"
        )
        #expect(
            Self.containsMessageSequenceMaximumBufferedMessages(in: bus),
            "Bus must declare an explicit internal messageSequenceMaximumBufferedMessages bound"
        )
        #expect(
            Self.messagePumpEnqueueUsesBoundedOverflowHandling(enqueue: enqueue, messagePump: messagePump),
            "Bus.MessagePump.enqueue must apply bounded overflow handling when no waiter is pending"
        )
        #expect(
            !Self.messagePumpEnqueueHasUnguardedNoWaiterAppend(enqueue),
            "Bus.MessagePump.enqueue must not fall back to an unguarded state.queue.append(message) no-waiter path"
        )
        #expect(
            !Self.containsRawGstMessagePointerStorage(in: sequencePath),
            "Bus.Messages and its watch pump must not store or queue raw GstMessage pointers"
        )
        #expect(
            shimHeader.contains("SwiftGstBusWatchRegistration")
                && shimSource.contains("SwiftGstBusWatchRegistration"),
            "C shim must expose the internal SwiftGstBusWatchRegistration type"
        )
        #expect(
            shimSource.contains("gst_bus_create_watch")
                && shimSource.contains("GMainContext")
                && (shimSource.contains("GThread") || shimSource.contains("g_thread_new")),
            "C shim must create a GstBus watch on a private GMainContext and native thread"
        )
        #expect(
            shimHeader.contains("swift_gst_bus_watch_start")
                && shimHeader.contains("swift_gst_bus_watch_stop")
                && shimSource.contains("swift_gst_bus_watch_start")
                && shimSource.contains("swift_gst_bus_watch_stop"),
            "C shim must provide start/stop functions for the internal bus watch registration"
        )
        #expect(
            shimSource.contains("g_thread_self")
                && shimSource.contains("cleanup_on_thread_exit")
                && shimSource.contains("g_thread_unref"),
            "C shim stop must avoid joining the watch thread from its own callback path"
        )
        #expect(
            Self.messageSequenceDocsDescribeWatchBackedSemantics(messageSequenceDocs),
            "Docs must describe messageSequence(filter:) as watch-backed and remove old demand-time polling claims"
        )
    }

    @Test("Reliable callback registrations keep contexts alive through C retain callbacks")
    func reliableCallbackRegistrationsKeepContextsAliveThroughCRetainCallbacks() throws {
        let root = try Self.packageRoot()
        let liveSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioSourceReliableDelivery.swift")
        )
        let fileSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let busSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let liveBridge = try Self.bracedDeclaration(
            beginningWith: "private final class LiveAudioReliablePacketBridge",
            in: liveSource
        )
        let liveStartCallbacks = try Self.bracedDeclaration(beginningWith: "func startCallbacks()", in: liveBridge)
        let activeCandidate = try Self.bracedDeclaration(
            beginningWith: "private final class ActiveCandidate",
            in: fileSource
        )
        let activeCandidateInit = try Self.bracedDeclaration(beginningWith: "init(", in: activeCandidate)
        let messagePump = (try? Self.bracedDeclaration(beginningWith: "fileprivate final class MessagePump", in: busSource))
            ?? (try? Self.bracedDeclaration(beginningWith: "private final class MessagePump", in: busSource))
            ?? ""
        let startWatch = try Self.bracedDeclaration(beginningWith: "private func startWatch()", in: messagePump)
        let reliableRegistrationCalls = [
            "swift_gst_app_sink_connect_new_sample",
            "swift_gst_app_sink_connect_eos",
            "swift_gst_bus_connect_sync_message_observer",
        ]

        #expect(
            Self.callsAreCoveredByWithExtendedLifetimeContext(
                source: liveStartCallbacks,
                calls: reliableRegistrationCalls
            ),
            "LiveAudioReliablePacketBridge.startCallbacks must wrap all callback registrations in withExtendedLifetime(context)"
        )
        #expect(
            Self.callsAreCoveredByWithExtendedLifetimeContext(
                source: activeCandidateInit,
                calls: reliableRegistrationCalls
            ),
            "ActiveCandidate.init must wrap all callback registrations in withExtendedLifetime(context)"
        )
        #expect(
            Self.callsAreCoveredByWithExtendedLifetimeContext(
                source: startWatch,
                calls: ["swift_gst_bus_watch_start"]
            ),
            "Bus.MessagePump.startWatch must keep its BusWatchCallbackContext alive through swift_gst_bus_watch_start"
        )
        #expect(
            Self.busWatchRegistrationAssignmentFollowsSuccessfulStart(startWatch),
            "Bus.MessagePump.startWatch must assign registration only after swift_gst_bus_watch_start succeeds"
        )
    }

    @Test("Callback registration destruction is claimed under its mutex")
    func callbackRegistrationDestructionIsClaimedUnderMutex() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Sources/CGStreamerShim/GStreamerAppShim.c")
        )
        let registration = try Self.bracedDeclaration(
            beginningWith: "struct SwiftGstCallbackRegistration",
            in: source
        )
        let claimFunctionName = (try? Self.callbackRegistrationDestroyClaimFunctionName(in: source))
            ?? "__missing_callback_registration_destroy_claim__"
        let claimFunction = (try? Self.cFunctionDeclaration(
            containing: "registration->destroying = TRUE",
            in: source
        )) ?? ""
        let finalizerFunctionName = (try? Self.callbackRegistrationFinalizerFunctionName(in: source))
            ?? "__missing_callback_registration_finalizer__"
        let finalizerFunction = (try? Self.cFunctionDeclaration(
            containing: "g_free(registration)",
            in: source
        )) ?? ""
        let beginFunction = try Self.bracedDeclaration(
            beginningWith: "static gboolean swift_gst_callback_registration_begin",
            in: source
        )
        let endFunction = try Self.bracedDeclaration(
            beginningWith: "static void swift_gst_callback_registration_end",
            in: source
        )
        let signalDestroyFunction = try Self.bracedDeclaration(
            beginningWith: "static void swift_gst_callback_registration_signal_destroy",
            in: source
        )
        let disconnectFunction = try Self.bracedDeclaration(
            beginningWith: "void swift_gst_callback_registration_disconnect",
            in: source
        )
        let connectFunctions: [(name: String, source: String)] = [
            (
                "new-sample",
                try Self.bracedDeclaration(
                    beginningWith: "SwiftGstCallbackRegistration* swift_gst_app_sink_connect_new_sample",
                    in: source
                )
            ),
            (
                "eos",
                try Self.bracedDeclaration(
                    beginningWith: "SwiftGstCallbackRegistration* swift_gst_app_sink_connect_eos",
                    in: source
                )
            ),
            (
                "sync-message",
                try Self.bracedDeclaration(
                    beginningWith: "SwiftGstCallbackRegistration* swift_gst_bus_connect_sync_message_observer",
                    in: source
                )
            ),
        ]
        let missingLockedClaims = connectFunctions
            .filter { !Self.connectFailureRollbackClaimsDestroy($0.source, claimFunctionName: claimFunctionName) }
            .map(\.name)
        let missingRollbackStateBeforeClaim = connectFunctions
            .filter {
                !Self.connectFailureRollbackSetsStateBeforeClaimingDestroy(
                    $0.source,
                    claimFunctionName: claimFunctionName
                )
            }
            .map(\.name)
        var finalizerCallContexts: [(name: String, source: String)] = [
            ("end", endFunction),
            ("signal-destroy", signalDestroyFunction),
            ("disconnect", disconnectFunction),
        ]
        finalizerCallContexts += connectFunctions.map {
            ("\($0.name) connect failure", Self.connectFailureRollbackBranch(in: $0.source) ?? "")
        }
        let missingFinalizerCallsAfterUnlock = finalizerCallContexts
            .filter {
                !Self.callbackRegistrationFinalizerCallsHappenAfterUnlock(
                    in: $0.source,
                    finalizerFunctionName: finalizerFunctionName
                )
            }
            .map(\.name)

        #expect(
            registration.contains("gboolean destroying"),
            "SwiftGstCallbackRegistration must track an in-progress destroy claim"
        )
        #expect(
            !Self.containsOldCallbackRegistrationUnlockThenDestroyPattern(in: source),
            "Remove old unlock-then-destroy try_destroy/should_destroy pattern"
        )
        #expect(
            Self.destroyClaimChecksStateAndMarksDestroying(in: claimFunction),
            "Destroy claim helper must check signal_destroyed, in_flight == 0, and !destroying before setting destroying = TRUE"
        )
        #expect(
            Self.callbackRegistrationFinalizerBodyHasRequiredOperations(finalizerFunction),
            "Callback registration finalizer must contain only the required release, bus-disable, unref, mutex-clear, and free operations"
        )
        #expect(
            Self.beginRetainsContextAfterUnlock(beginFunction),
            "callback_registration_begin must retain the in-flight context after unlocking registration->mutex"
        )
        #expect(
            Self.registrationMutexLockedSections(in: endFunction)
                .contains { Self.containsCallbackRegistrationDestroyClaim($0, claimFunctionName: claimFunctionName) },
            "callback_registration_end must attempt the destroy claim while registration->mutex is locked"
        )
        #expect(
            Self.endReleasesContextBeforeDecrementingInFlight(endFunction),
            "callback_registration_end must release the in-flight context retain before locking and decrementing in_flight"
        )
        #expect(
            Self.registrationMutexLockedSections(in: signalDestroyFunction)
                .contains { Self.containsCallbackRegistrationDestroyClaim($0, claimFunctionName: claimFunctionName) },
            "signal destroy notify must attempt the destroy claim while registration->mutex is locked"
        )
        #expect(
            Self.signalDestroySetsStateBeforeClaimingUnderLock(
                signalDestroyFunction,
                claimFunctionName: claimFunctionName
            ),
            "signal destroy notify must set disconnected, signal_destroyed, and handler_id before claiming under lock"
        )
        #expect(
            Self.disconnectAlreadyDisconnectedBranchClaimsDestroy(disconnectFunction, claimFunctionName: claimFunctionName),
            "disconnect() must claim destroy under lock when registration is already disconnected"
        )
        #expect(
            Self.disconnectNoHandlerBranchClaimsDestroy(disconnectFunction, claimFunctionName: claimFunctionName),
            "disconnect() must claim destroy under lock when there is no signal handler to disconnect"
        )
        #expect(
            missingLockedClaims.isEmpty,
            "Connect failure rollback branches must claim destroy under lock: \(missingLockedClaims.joined(separator: ", "))"
        )
        #expect(
            missingRollbackStateBeforeClaim.isEmpty,
            "Connect failure rollback branches must set disconnected/signal_destroyed before claiming: \(missingRollbackStateBeforeClaim.joined(separator: ", "))"
        )
        #expect(
            missingFinalizerCallsAfterUnlock.isEmpty,
            "Finalizer calls must happen after g_mutex_unlock(&registration->mutex): \(missingFinalizerCallsAfterUnlock.joined(separator: ", "))"
        )
    }

    @Test("Live reliable startup rollback marks unstored new-sample callback disconnected")
    func liveReliableStartupRollbackMarksUnstoredNewSampleCallbackDisconnected() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioSourceReliableDelivery.swift")
        )
        let liveBridge = try Self.bracedDeclaration(
            beginningWith: "private final class LiveAudioReliablePacketBridge",
            in: source
        )
        let startCallbacks = try Self.bracedDeclaration(beginningWith: "func startCallbacks()", in: liveBridge)
        let cleanupCallbacks = try Self.bracedDeclaration(
            beginningWith: "private func cleanupCallbacks()",
            in: liveBridge
        )

        #expect(
            Self.rollbackBranchesDisconnectingUnstoredNewSampleMarkCallbackState(in: startCallbacks),
            "Rollback branches that disconnect an unstored newSampleRegistration must mark callbackState.newSampleDisconnected"
        )
        #expect(
            cleanupCallbacks.contains("newSample: !state.newSampleDisconnected")
                && cleanupCallbacks.contains("state.newSampleDisconnected = true")
                && cleanupCallbacks.contains("probeState.decrementNewSampleHandlerCount()"),
            "cleanupCallbacks must gate new-sample handler decrementing on callbackState.newSampleDisconnected"
        )
    }

    @Test("Audio file reliable packet duration delegates shared clamping conversion")
    func audioFileReliablePacketDurationDelegatesSharedClampingConversion() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let durationExtension = try Self.bracedDeclaration(beginningWith: "private extension Duration", in: source)
        let conversion = try Self.bracedDeclaration(
            beginningWith: "var nanosecondsForReliablePackets",
            in: durationExtension
        )

        #expect(
            conversion.contains("ReliableDurationConversion.nanosecondsClampingNegativeToZero(self)"),
            "Duration.nanosecondsForReliablePackets must delegate to the shared reliable duration conversion helper"
        )
        #expect(
            conversion.range(
                of: #"UInt64\s*\(\s*seconds\s*\)\s*\*\s*1_000_000_000"#,
                options: .regularExpression
            ) == nil,
            "Duration.nanosecondsForReliablePackets must not perform raw UInt64(seconds) * 1_000_000_000 arithmetic"
        )
        #expect(
            !conversion.contains("self.components"),
            "Duration.nanosecondsForReliablePackets should not duplicate Duration component conversion logic"
        )
    }

    @Test("Audio file startup timeout transition is atomic under state lock")
    func audioFileStartupTimeoutTransitionIsAtomicUnderStateLock() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let reliableSource = try Self.bracedDeclaration(
            beginningWith: "private final class AudioFileReliablePacketSource",
            in: source
        )

        #expect(
            Self.containsAtomicStartupTimeoutTransition(in: reliableSource),
            "Startup timeout handling must atomically check active candidate, shutdown, and delivered-first-packet before setting terminalError and resuming pending outside the lock"
        )
    }

    @Test("Audio file reliable packet empty samples yield before retrying pulls")
    func audioFileReliablePacketEmptySamplesYieldBeforeRetryingPulls() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let reliableSource = try Self.bracedDeclaration(
            beginningWith: "private final class AudioFileReliablePacketSource",
            in: source
        )
        let nextPacket = try Self.bracedDeclaration(
            beginningWith: "private func nextPacket(from active",
            in: reliableSource
        )
        let pullPacket = try Self.bracedDeclaration(
            beginningWith: "private func pullPacket(from active",
            in: reliableSource
        )

        #expect(
            !Self.pullPacketContainsZeroSizeContinueBranch(pullPacket),
            "AudioFileReliablePacketSource.pullPacket(from:) must not spin on zero-size samples with a continue branch"
        )
        #expect(
            Self.nextPacketHasSkippedEmptyYieldAndTerminalChecks(nextPacket),
            "AudioFileReliablePacketSource.nextPacket(from:) must yield after skipped empty samples and check terminal state before the next nonblocking pull"
        )
    }

    @Test("Live reliable discontinuity detection keeps caps C API outside packet lock")
    func liveReliableDiscontinuityDetectionKeepsCapsCAPIOutsidePacketLock() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioSourceReliableDelivery.swift")
        )
        let packetState = try Self.bracedDeclaration(beginningWith: "private struct PacketState", in: source)
        let detectDiscontinuity = try Self.bracedDeclaration(
            beginningWith: "private func detectDiscontinuity",
            in: source
        )
        let lockBodies = try Self.bracedBlocks(after: "packetState.withLock", in: detectDiscontinuity)
        let disallowedCapsCalls = [
            "swift_gst_caps_is_equal",
            "swift_gst_caps_ref",
            "swift_gst_caps_unref",
        ]
        var lockViolations: [String] = []

        for (index, body) in lockBodies.enumerated() {
            for call in disallowedCapsCalls where body.contains(call) {
                lockViolations.append("withLock #\(index + 1): \(call)")
            }
        }

        #expect(!lockBodies.isEmpty, "detectDiscontinuity should still synchronize packet state updates")
        #expect(
            lockViolations.isEmpty,
            "detectDiscontinuity must not call caps equality/ref/unref APIs while packetState is locked:\n\(lockViolations.joined(separator: "\n"))"
        )
        #expect(
            !Self.containsPreviousCapsDestructionInsidePacketLock(in: lockBodies),
            "detectDiscontinuity must move old retained caps out of packetState.withLock before destruction"
        )
        #expect(
            Self.containsDiscontinuityRetryVersionPattern(
                packetState: packetState,
                detectDiscontinuity: detectDiscontinuity
            ),
            "detectDiscontinuity must use a retry loop with a packet-state version token before committing caps/discontinuity updates"
        )
    }

    @Test("ReliablePackets public API surface remains source-compatible")
    func reliablePacketsPublicAPISurfaceRemainsSourceCompatible() throws {
        let root = try Self.packageRoot()
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))

        #expect(
            Self.containsStructConformance(
                typeName: "ReliablePackets",
                genericClause: "<Element: Sendable>",
                conformances: ["AsyncSequence", "Sendable"],
                in: source
            ),
            "ReliablePackets must be public, generic over Sendable elements, and conform to AsyncSequence + Sendable"
        )
        #expect(
            Self.containsNestedIteratorConformance(in: source),
            "ReliablePackets.AsyncIterator must conform to AsyncIteratorProtocol + Sendable"
        )
        #expect(
            Self.containsReliableNextSignature(in: source),
            "ReliablePackets.AsyncIterator.next() must be @concurrent/equivalent and async throws -> Element?"
        )
        #expect(
            source.range(
                of: #"public\s+func\s+makeAsyncIterator\(\)\s*->\s*AsyncIterator"#,
                options: .regularExpression
            ) != nil,
            "ReliablePackets must expose public makeAsyncIterator() -> AsyncIterator"
        )
    }

    @Test("Audio file source API exposes only the reliable file/decode surface")
    func audioFileSourceAPIExposesOnlyReliableFileDecodeSurface() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let microphoneBuilder = try Self.bracedDeclaration(beginningWith: "public struct AudioSourceBuilder", in: audioSource)

        #expect(source.contains("public static func file(path: String) -> AudioFileSourceBuilder"))
        #expect(Self.containsSendableType("AudioFileSourceBuilder", in: source))
        #expect(Self.containsSendableType("AudioFileSource", in: source))
        #expect(source.contains("public func build() throws -> AudioFileSource"))
        #expect(source.contains("public func withEncoding(_ encoding: AudioSource.Encoding) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withOpusEncoding(bitrate: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withAACEncoding(bitrate: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withFormat(_ format: AudioFormat) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withSampleRate(_ rate: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withChannels(_ channels: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("case raw"))
        #expect(source.contains("case opus(bitrate: Int)"))
        #expect(source.contains("case aac(bitrate: Int)"))
        #expect(source.contains("public func reliablePackets() -> ReliablePackets<Buffer>"))
        #expect(!microphoneBuilder.contains("reliablePackets("))
    }

    @Test("RFC-002 live reliable audio public API surface is additive and scoped")
    func rfc002LiveReliableAudioPublicAPISurfaceIsAdditiveAndScoped() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let audioFileSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let videoSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/VideoSource.swift"))
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let audioSourceClass = try Self.bracedDeclaration(beginningWith: "public final class AudioSource", in: audioSource)
        let audioBuilder = try Self.bracedDeclaration(beginningWith: "public struct AudioSourceBuilder", in: audioSource)
        let videoSourceClass = try Self.bracedDeclaration(beginningWith: "public final class VideoSource", in: videoSource)
        let videoBuilder = try Self.bracedDeclaration(beginningWith: "public struct VideoSourceBuilder", in: videoSource)
        let audioFileSourceType = try Self.bracedDeclaration(beginningWith: "public struct AudioFileSource", in: audioFileSource)

        #expect(
            Self.containsReliableDeliveryBuilderSignature(in: audioBuilder),
            "AudioSourceBuilder.withReliableDelivery must default to leaky: .none, maxBuffers: 256, maxBytes: nil, maxTime: .seconds(2)"
        )
        #expect(
            audioSourceClass.range(
                of: #"public\s+func\s+reliablePackets\(\)\s+throws\s*->\s*ReliablePackets<\s*ReliablePacket<\s*Buffer\s*>\s*>"#,
                options: .regularExpression
            ) != nil,
            "AudioSource must expose reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>>"
        )
        #expect(
            audioSourceClass.range(
                of: #"public\s+func\s+finalize\(\s*timeout:\s*Duration\s*=\s*\.seconds\(\s*5\s*\)\s*\)\s+async\s+throws"#,
                options: .regularExpression
            ) != nil,
            "AudioSource.finalize(timeout:) must default to .seconds(5)"
        )
        #expect(
            Self.containsReliablePacketDeclaration(in: source),
            "ReliablePacket must be public, generic over Sendable payloads, and Sendable"
        )
        #expect(
            Self.containsDiscontinuityDeclarationWithExactKinds(in: source),
            "Discontinuity.Kind must expose exactly formatChange, discont, gap, and dropped"
        )
        #expect(
            !source.contains("public enum LiveSourceDeliveryPolicy")
                && !source.contains("public struct LiveSourceDeliveryPolicy")
                && !source.contains("public final class LiveSourceDeliveryPolicy"),
            "RFC-002 must not add a public LiveSourceDeliveryPolicy type"
        )
        #expect(
            !videoSourceClass.contains("public func reliablePackets("),
            "RFC-002 is audio-only; VideoSource must not expose reliablePackets()"
        )
        #expect(
            !videoBuilder.contains("public func withReliableDelivery("),
            "RFC-002 is audio-only; VideoSourceBuilder must not expose withReliableDelivery(...)"
        )
        #expect(
            audioFileSourceType.contains("public func reliablePackets() -> ReliablePackets<Buffer>"),
            "AudioFileSource.reliablePackets() must remain source-compatible"
        )
    }

    @Test("Audio file build remains lazy until reliable packet iteration starts")
    func audioFileBuildRemainsLazyUntilReliablePacketIterationStarts() throws {
        let root = try Self.packageRoot()
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let builder = try Self.bracedDeclaration(beginningWith: "public struct AudioFileSourceBuilder", in: source)
        let build = try Self.bracedDeclaration(beginningWith: "public func build() throws -> AudioFileSource", in: builder)

        #expect(build.contains("GStreamerError.invalidArgument"))
        #expect(!build.contains("Pipeline("))
        #expect(!build.contains(".play()"))
        #expect(!build.contains("setState(.playing)"))
    }

    @Test("Reliable audio file construction does not interpolate raw file paths or URIs")
    func reliableAudioFileConstructionDoesNotInterpolateRawFilePathsOrURIs() throws {
        let root = try Self.packageRoot()
        let files = try Self.recursiveRegularFiles(in: root.appendingPathComponent("Sources/GStreamer")) { file in
            file.pathExtension == "swift"
        }
        let disallowedSnippets = [
            #"file://\(path)"#,
            #"file://\(url.path)"#,
            #"uri=\(uri)"#,
            #"uri=\(path)"#,
            #"uri=\(filePath)"#,
            #"location=\(path)"#,
            #"URIDecodeSource(uri: "file://\(path)")"#,
        ]
        var violations: [String] = []

        for file in files {
            let contents = try Self.contents(of: file)
            let scansReliableAudioConstruction = contents.contains("AudioFileSource")
                || contents.contains("ReliablePackets")
                || file.lastPathComponent == "URIDecodeSource.swift"

            guard scansReliableAudioConstruction else { continue }

            for snippet in disallowedSnippets where contents.contains(snippet) {
                violations.append("\(Self.relativePath(file, to: root)): \(snippet)")
            }
        }

        #expect(
            violations.isEmpty,
            "Use URL/path property escaping instead of raw interpolation in file/decode pipeline construction:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Reliable bridge is pull based, cancellable, and non-dropping")
    func reliableBridgeIsPullBasedCancellableAndNonDropping() throws {
        let root = try Self.packageRoot()
        let reliablePackets = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/ReliablePackets.swift")
        )
        let audioFileSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let reliableSource = try Self.bracedDeclaration(
            beginningWith: "private final class AudioFileReliablePacketSource",
            in: audioFileSource
        )
        let activeCandidate = try Self.bracedDeclaration(
            beginningWith: "private final class ActiveCandidate",
            in: audioFileSource
        )
        let source = [reliablePackets, reliableSource, activeCandidate].joined(separator: "\n")

        #expect(source.contains("withTaskCancellationHandler"))
        #expect(source.contains("swift_gst_app_sink_try_pull_sample"))
        #expect(!source.contains("swift_gst_app_sink_pull_sample"))
        #expect(!source.contains(".bufferingNewest"))
        #expect(!source.contains(".bufferingOldest"))
    }

    @Test("Realtime AudioSource.packets stays delegated and lossy")
    func realtimeAudioSourcePacketsStaysDelegatedAndLossy() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let publicPackets = try Self.bracedDeclaration(
            beginningWith: "public func packets() -> AsyncStream<Buffer>",
            in: audioSource
        )
        let audioPacketSink = try Self.bracedDeclaration(
            beginningWith: "private final class AudioPacketSink",
            in: audioSource
        )
        let delegatedPackets = try Self.bracedDeclaration(
            beginningWith: "func packets() -> AsyncStream<Buffer>",
            in: audioPacketSink
        )

        #expect(publicPackets.contains("return packetSink.packets()"))
        #expect(
            Self.containsBufferingNewestPolicy(
                source: audioSource,
                implementation: delegatedPackets,
                expectedCount: 8
            )
        )
        #expect(audioSource.contains("drop=true"))
        #expect(audioSource.contains("max-buffers=1"))
    }

    @Test("Bus-derived streams keep non-dropping buffering behavior")
    func busDerivedStreamsDoNotUseDroppingBufferPolicies() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let declarations = [
            "public func messages",
            "public func errors()",
            "public func warnings()",
            "public func stateChanges()",
        ]
        var violations: [String] = []

        for declaration in declarations {
            let implementation = try Self.bracedDeclaration(beginningWith: declaration, in: source)
            if implementation.contains(".bufferingNewest") || implementation.contains(".bufferingOldest") {
                violations.append(declaration)
            }
        }

        #expect(
            violations.isEmpty,
            "Bus-derived streams must not use dropping AsyncStream policies:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Encoded packet docs describe best-effort realtime backpressure")
    func audioSourcePacketDocsDescribeBestEffortRealtimeBackpressure() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let docs = try Self.leadingDocumentationComment(
            for: "public func packets() -> AsyncStream<Buffer>",
            in: source
        )
        let normalized = docs.lowercased()

        #expect(normalized.contains("best-effort") || normalized.contains("best effort"))
        #expect(normalized.contains("realtime") || normalized.contains("real-time"))
        #expect(normalized.contains("drop"))
        #expect(normalized.contains("older"))
        #expect(
            normalized.contains("slow-consumer")
                || normalized.contains("slow consumer")
                || normalized.contains("backpressure")
        )
    }

    @Test("README documents GStreamer dependency preflight")
    func readmeDocumentsGStreamerDependencyPreflight() throws {
        let root = try Self.packageRoot()
        let readme = try Self.contents(of: root.appendingPathComponent("README.md"))
        let normalized = readme.lowercased()
        let requiredSnippets = [
            "pkgconf",
            "pkg-config",
            "gstreamer-1.0",
            "gstreamer-app-1.0",
            "gstreamer-video-1.0",
            "pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0",
            "brew install pkgconf gstreamer",
            "libgstreamer1.0-dev",
            "libgstreamer-plugins-base1.0-dev",
            "pkgconf-pkg-config",
            "gstreamer1-devel",
            "gstreamer1-plugins-base-devel",
        ]
        let missing = requiredSnippets.filter { !normalized.contains($0) }

        #expect(
            missing.isEmpty,
            "README is missing dependency/preflight guidance:\n\(missing.joined(separator: "\n"))"
        )
    }

    @Test("Device monitor tests do not silently skip on macOS CI")
    func deviceMonitorTestsDoNotUseSilentCISkipReturns() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Tests/SwiftGStreamerTests/DeviceMonitorTests.swift")
        )
        let disallowedSnippets = [
            "shouldSkipOnMacOSCI",
            "guard !shouldSkipOnMacOSCI() else { return }",
        ]
        let violations = disallowedSnippets.filter { source.contains($0) }

        #expect(
            violations.isEmpty,
            "DeviceMonitorTests must use deterministic zero-or-more assertions or Swift Testing traits, not silent returns:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Async media smoke tests keep post-loop evidence assertions")
    func asyncMediaSmokeTestsKeepPostLoopEvidenceAssertions() throws {
        let root = try Self.packageRoot()
        let requirements: [(file: String, declaration: String, snippets: [String])] = [
            (
                "Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift",
                "func videoFrameData() async throws",
                ["#require(firstFrame", "#expect(frame.bytes.byteCount == 4 * 4 * 4)"]
            ),
            (
                "Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift",
                "func consistentFormat() async throws",
                ["#require(formats.count >= 3", "#expect(formats.allSatisfy"]
            ),
            (
                "Tests/SwiftGStreamerTests/CVPixelBufferTests.swift",
                "func convertBGRAFrame() async throws",
                ["#require(firstFrame", "#require(pixelBuffer"]
            ),
            (
                "Tests/SwiftGStreamerTests/CVPixelBufferTests.swift",
                "func convertNV12Frame() async throws",
                ["#require(firstFrame", "#require(pixelBuffer"]
            ),
            (
                "Tests/SwiftGStreamerTests/CVPixelBufferTests.swift",
                "func convertI420Frame() async throws",
                ["#require(firstFrame", "#require(pixelBuffer"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func videoFrameHasPTS() async throws",
                ["#require(frame.pts", "#expect(frameCount == 3)"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func videoFrameHasDuration() async throws",
                ["#require(firstFrame", "#require(frame.duration"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func appSourcePTSPreserved() async throws",
                ["#require(firstFrame", "#require(frame.pts", "#require(frame.duration"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func calculateFPS() async throws",
                ["#require(firstFrame", "#require(frame.duration"]
            ),
            (
                "Tests/SwiftGStreamerTests/AudioTests.swift",
                "func audioBufferHasTimestamps() async throws",
                ["#require(firstBuffer", "#require(buffer.pts"]
            ),
            (
                "Tests/SwiftGStreamerTests/AudioTests.swift",
                "func audioBufferSampleCount() async throws",
                ["#require(firstBuffer", "#require(buffer.format == .s16le", "#require(buffer.channels == 2"]
            ),
        ]

        var missing: [String] = []
        for requirement in requirements {
            let source = try Self.contents(of: root.appendingPathComponent(requirement.file))
            let declaration = try Self.bracedDeclaration(beginningWith: requirement.declaration, in: source)

            for snippet in requirement.snippets where !declaration.contains(snippet) {
                missing.append("\(requirement.file) \(requirement.declaration): \(snippet)")
            }
        }

        #expect(
            missing.isEmpty,
            "Async smoke tests must prove awaited evidence before dependent assertions:\n\(missing.joined(separator: "\n"))"
        )
    }

    private static func staleVideoFrameReferencePatterns() -> [String] {
        let frameReceiver = "frame."
        let mappedAccess = "withMappedBytes"
        return [
            frameReceiver + mappedAccess,
            "VideoFrame/" + mappedAccess,
            frameReceiver + "mutableBytes",
            frameReceiver + "withUnsafeMutableBytes",
        ]
    }

    private static func containsMutableMigrationGuidance(_ documentation: String) -> Bool {
        let normalized = documentation.lowercased()
        let mentionsMutation = [
            "mutation",
            "mutate",
            "mutating",
            "modify",
            "modifying",
            "write",
            "writable",
        ].contains { normalized.contains($0) }
        let explainsCopy = normalized.contains("copy") || normalized.contains("copying")
        let namesBuffer = normalized.contains("buffer")
        let namesMutableDestination = normalized.contains("mutable structure")
            || normalized.contains("mutable data structure")
            || normalized.contains("another mutable")

        return mentionsMutation && explainsCopy && namesBuffer && namesMutableDestination
    }

    private static func videoFrameReferenceScanFiles(in root: URL) throws -> [URL] {
        var files = [root.appendingPathComponent("README.md")]
        files += try recursiveRegularFiles(in: root.appendingPathComponent("Examples")) { _ in
            true
        }
        files += try recursiveRegularFiles(in: root.appendingPathComponent("Tests")) { _ in
            true
        }
        files += try recursiveRegularFiles(in: root.appendingPathComponent("Sources/GStreamer")) { file in
            file.pathExtension == "swift" || file.path.contains(".docc/")
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func combinedSwiftSources(in directory: URL) throws -> String {
        let files = try recursiveRegularFiles(in: directory) { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        let chunks = try files.map { file in
            try "// \(file.lastPathComponent)\n" + contents(of: file)
        }
        return chunks.joined(separator: "\n")
    }

    private static func recursiveRegularFiles(
        in directory: URL,
        including shouldInclude: (URL) -> Bool
    ) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, shouldInclude(file) else {
                continue
            }
            files.append(file)
        }
        return files
    }

    private static func packageRoot(filePath: String = #filePath) throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while true {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw StaticAPISafetyError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private static func relativePath(_ file: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath + "/"

        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return filePath
    }

    private static func declarationSignature(_ declaration: String) -> String {
        declaration
            .split(separator: "{", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? declaration
    }

    private static func normalizedWhitespace(_ source: String) -> String {
        source.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func callbackRegistrationDestroyClaimFunctionName(in source: String) throws -> String {
        let declaration = try cFunctionDeclaration(
            containing: "registration->destroying = TRUE",
            in: source
        )
        let signature = declarationSignature(declaration)

        if let claimName = firstCapture(
            #"\b(swift_gst_callback_registration_[A-Za-z0-9_]*claim[A-Za-z0-9_]*)\s*\("#,
            in: signature
        ) {
            return claimName
        }

        if let destroyName = firstCapture(
            #"\b(swift_gst_callback_registration_[A-Za-z0-9_]*destroy[A-Za-z0-9_]*)\s*\("#,
            in: signature
        ) {
            return destroyName
        }

        throw StaticAPISafetyError.declarationNotFound("callback registration destroy claim helper")
    }

    private static func containsOldCallbackRegistrationUnlockThenDestroyPattern(in source: String) -> Bool {
        let oldUnlockThenDestroyPattern = #"(?s)should_destroy\s*=\s*registration->signal_destroyed\s*&&\s*registration->in_flight\s*==\s*0\s*;\s*g_mutex_unlock\s*\(\s*&registration->mutex\s*\)\s*;\s*if\s*\(\s*!\s*should_destroy\s*\)"#
        return source.range(of: oldUnlockThenDestroyPattern, options: .regularExpression) != nil
            || source.range(
                of: #"\bswift_gst_callback_registration_try_destroy\s*\("#,
                options: .regularExpression
            ) != nil
    }

    private static func destroyClaimChecksStateAndMarksDestroying(in source: String) -> Bool {
        let checksSignalDestroyed = source.contains("registration->signal_destroyed")
        let checksInFlightZero = source.range(
            of: #"registration->in_flight\s*==\s*0|0\s*==\s*registration->in_flight"#,
            options: .regularExpression
        ) != nil
        let checksNotDestroying = source.range(
            of: #"!\s*registration->destroying|registration->destroying\s*==\s*FALSE|FALSE\s*==\s*registration->destroying"#,
            options: .regularExpression
        ) != nil
        let setsDestroying = source.range(
            of: #"registration->destroying\s*=\s*TRUE"#,
            options: .regularExpression
        ) != nil

        return checksSignalDestroyed && checksInFlightZero && checksNotDestroying && setsDestroying
    }

    private static func callbackRegistrationFinalizerFunctionName(in source: String) throws -> String {
        let declaration = try cFunctionDeclaration(
            containing: "g_free(registration)",
            in: source
        )
        let signature = declarationSignature(declaration)

        if let finalizerName = firstCapture(
            #"\b(swift_gst_callback_registration_[A-Za-z0-9_]*)\s*\("#,
            in: signature
        ) {
            return finalizerName
        }

        throw StaticAPISafetyError.declarationNotFound("callback registration finalizer")
    }

    private static func callbackRegistrationFinalizerBodyHasRequiredOperations(_ source: String) -> Bool {
        let requiredSingleCalls = [
            #"swift_gst_callback_registration_release_context\s*\(\s*registration\s*\)"#,
            #"gst_bus_disable_sync_message_emission\s*\(\s*GST_BUS\s*\(\s*registration->instance\s*\)\s*\)"#,
            #"g_object_unref\s*\(\s*registration->instance\s*\)"#,
            #"g_mutex_clear\s*\(\s*&registration->mutex\s*\)"#,
            #"g_free\s*\(\s*registration\s*\)"#,
        ]
        let hasRequiredCallsExactlyOnce = requiredSingleCalls.allSatisfy {
            regexMatchCount($0, in: source) == 1
        }
        let hasBusDisableBranch = source.range(
            of: #"if\s*\(\s*registration->kind\s*==\s*SWIFT_GST_CALLBACK_BUS_SYNC_MESSAGE\s*\)\s*\{[^}]*gst_bus_disable_sync_message_emission\s*\(\s*GST_BUS\s*\(\s*registration->instance\s*\)\s*\)\s*;"#,
            options: .regularExpression
        ) != nil
        let requiredOperationsAppearInOrder = regexPatternsAppearInOrder(
            [
                #"swift_gst_callback_registration_release_context\s*\(\s*registration\s*\)"#,
                #"SWIFT_GST_CALLBACK_BUS_SYNC_MESSAGE"#,
                #"gst_bus_disable_sync_message_emission\s*\(\s*GST_BUS\s*\(\s*registration->instance\s*\)\s*\)"#,
                #"g_object_unref\s*\(\s*registration->instance\s*\)"#,
                #"g_mutex_clear\s*\(\s*&registration->mutex\s*\)"#,
                #"g_free\s*\(\s*registration\s*\)"#,
            ],
            in: source
        )
        let disallowedSnippets = [
            "g_mutex_lock(&registration->mutex)",
            "g_mutex_unlock(&registration->mutex)",
            "g_signal_",
            "g_object_ref",
            "gst_bus_enable_sync_message_emission",
            "swift_gst_callback_registration_retain_context",
            "swift_gst_callback_registration_claim_destroy_locked",
            "registration->disconnected",
            "registration->handler_id",
            "registration->signal_destroyed",
            "registration->in_flight",
            "registration->destroying",
        ]

        return hasRequiredCallsExactlyOnce
            && hasBusDisableBranch
            && requiredOperationsAppearInOrder
            && disallowedSnippets.allSatisfy { !source.contains($0) }
    }

    private static func containsCallbackRegistrationDestroyClaim(
        _ source: String,
        claimFunctionName: String
    ) -> Bool {
        if source.range(
            of: #"registration->destroying\s*=\s*TRUE"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let escapedName = NSRegularExpression.escapedPattern(for: claimFunctionName)
        return source.range(
            of: #"\b\#(escapedName)\s*\(\s*registration\s*\)"#,
            options: .regularExpression
        ) != nil
    }

    private static func callbackRegistrationDestroyClaimRange(
        in source: String,
        claimFunctionName: String
    ) -> Range<String.Index>? {
        if let directClaimRange = source.range(
            of: #"registration->destroying\s*=\s*TRUE"#,
            options: .regularExpression
        ) {
            return directClaimRange
        }

        return callbackRegistrationFunctionCallRanges(
            named: claimFunctionName,
            in: source
        ).first
    }

    private static func callbackRegistrationFinalizerCallsHappenAfterUnlock(
        in source: String,
        finalizerFunctionName: String
    ) -> Bool {
        let finalizerCalls = callbackRegistrationFunctionCallRanges(
            named: finalizerFunctionName,
            in: source
        )

        guard !finalizerCalls.isEmpty else {
            return false
        }

        return finalizerCalls.allSatisfy { finalizerCall in
            let prefix = source[..<finalizerCall.lowerBound]
            guard let unlockRange = prefix.range(
                of: "g_mutex_unlock(&registration->mutex);",
                options: .backwards
            ) else {
                return false
            }

            if let lockRange = prefix.range(
                of: "g_mutex_lock(&registration->mutex);",
                options: .backwards
            ) {
                return lockRange.lowerBound < unlockRange.lowerBound
            }

            return true
        }
    }

    private static func signalDestroySetsStateBeforeClaimingUnderLock(
        _ source: String,
        claimFunctionName: String
    ) -> Bool {
        registrationMutexLockedSections(in: source).contains {
            stateAssignmentsAppearBeforeClaim(
                in: $0,
                claimFunctionName: claimFunctionName,
                assignmentPatterns: [
                    #"registration->disconnected\s*=\s*TRUE"#,
                    #"registration->signal_destroyed\s*=\s*TRUE"#,
                    #"registration->handler_id\s*=\s*0"#,
                ]
            )
        }
    }

    private static func beginRetainsContextAfterUnlock(_ source: String) -> Bool {
        let retainFunctionName = "swift_gst_callback_registration_retain_context"
        let retainRanges = callbackRegistrationFunctionCallRanges(
            named: retainFunctionName,
            in: source
        )

        guard retainRanges.count == 1,
              let unlockRange = source.range(of: "g_mutex_unlock(&registration->mutex);")
        else {
            return false
        }

        let retainAfterUnlock = unlockRange.upperBound <= retainRanges[0].lowerBound
        let lockedSectionsDoNotRetain = registrationMutexLockedSections(in: source).allSatisfy {
            callbackRegistrationFunctionCallRanges(named: retainFunctionName, in: $0).isEmpty
        }

        return retainAfterUnlock && lockedSectionsDoNotRetain
    }

    private static func registrationMutexLockedSections(in source: String) -> [String] {
        let lock = "g_mutex_lock(&registration->mutex);"
        let unlock = "g_mutex_unlock(&registration->mutex);"
        var sections: [String] = []
        var searchStart = source.startIndex

        while let lockRange = source.range(of: lock, range: searchStart..<source.endIndex),
              let unlockRange = source.range(of: unlock, range: lockRange.upperBound..<source.endIndex)
        {
            sections.append(String(source[lockRange.lowerBound..<unlockRange.upperBound]))
            searchStart = unlockRange.upperBound
        }

        return sections
    }

    private static func endReleasesContextBeforeDecrementingInFlight(_ source: String) -> Bool {
        guard let releaseRange = source.range(
            of: "swift_gst_callback_registration_release_context(registration)"
        ) else {
            return false
        }
        guard let firstLockRange = source.range(of: "g_mutex_lock(&registration->mutex);") else {
            return false
        }

        let decrementPattern = #"registration->in_flight\s*(?:--|-=)\s*1?"#
        guard let decrementRange = source.range(of: decrementPattern, options: .regularExpression) else {
            return false
        }

        return releaseRange.lowerBound < firstLockRange.lowerBound
            && releaseRange.lowerBound < decrementRange.lowerBound
    }

    private static func disconnectAlreadyDisconnectedBranchClaimsDestroy(
        _ source: String,
        claimFunctionName: String
    ) -> Bool {
        registrationMutexLockedSections(in: source).contains { section in
            let elseBlocks = (try? bracedBlocks(after: "else", in: section)) ?? []
            return elseBlocks.contains {
                containsCallbackRegistrationDestroyClaim($0, claimFunctionName: claimFunctionName)
            }
        }
    }

    private static func disconnectNoHandlerBranchClaimsDestroy(
        _ source: String,
        claimFunctionName: String
    ) -> Bool {
        registrationMutexLockedSections(in: source).contains { section in
            let mentionsNoHandler = section.range(
                of: #"(?:registration->)?handler_id\s*(?:==|!=)\s*0"#,
                options: .regularExpression
            ) != nil
            return mentionsNoHandler
                && containsCallbackRegistrationDestroyClaim(section, claimFunctionName: claimFunctionName)
        }
    }

    private static func connectFailureRollbackClaimsDestroy(
        _ source: String,
        claimFunctionName: String
    ) -> Bool {
        guard let failureBranch = connectFailureRollbackBranch(in: source) else {
            return false
        }

        return registrationMutexLockedSections(in: failureBranch).contains {
            containsCallbackRegistrationDestroyClaim($0, claimFunctionName: claimFunctionName)
        }
    }

    private static func connectFailureRollbackSetsStateBeforeClaimingDestroy(
        _ source: String,
        claimFunctionName: String
    ) -> Bool {
        guard let failureBranch = connectFailureRollbackBranch(in: source) else {
            return false
        }

        return registrationMutexLockedSections(in: failureBranch).contains {
            stateAssignmentsAppearBeforeClaim(
                in: $0,
                claimFunctionName: claimFunctionName,
                assignmentPatterns: [
                    #"registration->disconnected\s*=\s*TRUE"#,
                    #"registration->signal_destroyed\s*=\s*TRUE"#,
                ]
            )
        }
    }

    private static func connectFailureRollbackBranch(in source: String) -> String? {
        try? bracedDeclaration(
            beginningWith: "if (registration->handler_id == 0)",
            in: source
        )
    }

    private static func stateAssignmentsAppearBeforeClaim(
        in source: String,
        claimFunctionName: String,
        assignmentPatterns: [String]
    ) -> Bool {
        guard let claimRange = callbackRegistrationDestroyClaimRange(
            in: source,
            claimFunctionName: claimFunctionName
        ) else {
            return false
        }

        let prefix = String(source[..<claimRange.lowerBound])
        return assignmentPatterns.allSatisfy {
            prefix.range(of: $0, options: .regularExpression) != nil
        }
    }

    private static func callbackRegistrationFunctionCallRanges(
        named functionName: String,
        in source: String
    ) -> [Range<String.Index>] {
        let escapedName = NSRegularExpression.escapedPattern(for: functionName)
        return regexRanges(
            #"\b\#(escapedName)\s*\(\s*registration\s*\)"#,
            in: source
        )
    }

    private static func regexMatchCount(_ pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }

        return regex.numberOfMatches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
    }

    private static func regexRanges(_ pattern: String, in source: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ).compactMap { Range($0.range, in: source) }
    }

    private static func regexPatternsAppearInOrder(_ patterns: [String], in source: String) -> Bool {
        var searchStart = source.startIndex

        for pattern in patterns {
            guard let range = regexRanges(pattern, in: source).first(where: { $0.lowerBound >= searchStart }) else {
                return false
            }
            searchStart = range.upperBound
        }

        return true
    }

    private static func cFunctionDeclaration(containing marker: String, in source: String) throws -> String {
        guard let markerRange = source.range(of: marker) else {
            throw StaticAPISafetyError.declarationNotFound(marker)
        }

        var index = source.startIndex
        var depth = 0
        var topLevelOpenBrace: String.Index?

        while index < markerRange.lowerBound {
            switch source[index] {
            case "{":
                if depth == 0 {
                    topLevelOpenBrace = index
                }
                depth += 1
            case "}":
                depth -= 1
            default:
                break
            }
            index = source.index(after: index)
        }

        guard let openBrace = topLevelOpenBrace else {
            throw StaticAPISafetyError.declarationNotFound(marker)
        }

        let prefix = source[..<openBrace]
        let start = prefix.range(of: "\n\n", options: .backwards)?.upperBound ?? source.startIndex
        let closeBrace = try closingBrace(for: openBrace, in: source, declaration: marker)
        return String(source[start...closeBrace])
    }

    private static func closingBrace(
        for openBrace: String.Index,
        in source: String,
        declaration: String
    ) throws -> String.Index {
        var index = openBrace
        var depth = 0

        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return index
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw StaticAPISafetyError.unbalancedDeclaration(declaration)
    }

    private static func firstCapture(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[captureRange])
    }

    private static func bracedDeclaration(beginningWith declaration: String, in source: String) throws -> String {
        guard let declarationRange = source.range(of: declaration) else {
            throw StaticAPISafetyError.declarationNotFound(declaration)
        }
        guard let openBrace = source[declarationRange.upperBound...].firstIndex(of: "{") else {
            throw StaticAPISafetyError.declarationNotFound(declaration)
        }

        var index = openBrace
        var depth = 0

        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[declarationRange.lowerBound...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw StaticAPISafetyError.unbalancedDeclaration(declaration)
    }

    private static func bracedBlocks(after marker: String, in source: String) throws -> [String] {
        var blocks: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            guard let openBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
                throw StaticAPISafetyError.declarationNotFound(marker)
            }

            var index = openBrace
            var depth = 0
            var foundEnd = false

            while index < source.endIndex {
                switch source[index] {
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        blocks.append(String(source[openBrace...index]))
                        searchStart = source.index(after: index)
                        foundEnd = true
                        break
                    }
                default:
                    break
                }
                if foundEnd {
                    break
                }
                index = source.index(after: index)
            }

            if !foundEnd {
                throw StaticAPISafetyError.unbalancedDeclaration(marker)
            }
        }

        return blocks
    }

    private static func bracedBlocksWithTrailing(
        after marker: String,
        in source: String,
        trailingLimit: Int
    ) throws -> [(block: String, trailing: String)] {
        var blocks: [(block: String, trailing: String)] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            guard let openBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
                throw StaticAPISafetyError.declarationNotFound(marker)
            }

            var index = openBrace
            var depth = 0
            var foundEnd = false

            while index < source.endIndex {
                switch source[index] {
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        let trailingStart = source.index(after: index)
                        let trailingEnd = source.index(
                            trailingStart,
                            offsetBy: trailingLimit,
                            limitedBy: source.endIndex
                        ) ?? source.endIndex
                        blocks.append((
                            block: String(source[openBrace...index]),
                            trailing: String(source[trailingStart..<trailingEnd])
                        ))
                        searchStart = source.index(after: index)
                        foundEnd = true
                        break
                    }
                default:
                    break
                }
                if foundEnd {
                    break
                }
                index = source.index(after: index)
            }

            if !foundEnd {
                throw StaticAPISafetyError.unbalancedDeclaration(marker)
            }
        }

        return blocks
    }

    private static func callsAreCoveredByWithExtendedLifetimeContext(
        source: String,
        calls: [String]
    ) -> Bool {
        guard let lifetimeBlocks = try? bracedBlocks(after: "withExtendedLifetime(context)", in: source),
              !lifetimeBlocks.isEmpty
        else {
            return false
        }

        return calls.allSatisfy { call in
            source.contains(call) && lifetimeBlocks.contains { $0.contains(call) }
        }
    }

    private static func busWatchRegistrationAssignmentFollowsSuccessfulStart(_ startWatch: String) -> Bool {
        let normalized = normalizedWhitespace(startWatch)
        guard
            normalized.range(of: #"guard\s+let\s+watch\s*="#, options: .regularExpression) != nil,
            let startRange = normalized.range(of: "swift_gst_bus_watch_start"),
            let assignmentRange = normalized.range(
                of: #"\bregistration\s*=\s*watch\b"#,
                options: .regularExpression
            )
        else {
            return false
        }

        let startsBeforeAssignment = startRange.upperBound <= assignmentRange.lowerBound
        let failurePathBeforeAssignment = normalized[..<assignmentRange.lowerBound]
            .contains("close(startupFailed: true)")

        return startsBeforeAssignment && failurePathBeforeAssignment
    }

    private static func rollbackBranchesDisconnectingUnstoredNewSampleMarkCallbackState(
        in startCallbacks: String
    ) -> Bool {
        guard let storageRange = startCallbacks.range(of: "self.newSampleRegistration = newSampleRegistration") else {
            return false
        }

        let registrationPrefix = String(startCallbacks[..<storageRange.lowerBound])
        let rollbackBodies = ((try? bracedBlocks(after: "else", in: registrationPrefix)) ?? [])
            .filter { $0.contains("swift_gst_callback_registration_disconnect(newSampleRegistration)") }

        guard !rollbackBodies.isEmpty else {
            return false
        }

        return rollbackBodies.allSatisfy { body in
            let directlyMarksState = body.contains("callbackState.withLock")
                && body.contains("newSampleDisconnected = true")
            let delegatesToMarker = body.range(
                of: #"\bmark\w*NewSample\w*Disconnected\s*\("#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil

            return directlyMarksState || delegatesToMarker
        }
    }

    private static func containsAtomicStartupTimeoutTransition(in source: String) -> Bool {
        guard source.contains("reportStartupTimeout") else {
            return false
        }

        let lockBlocks = (try? bracedBlocksWithTrailing(
            after: "state.withLock",
            in: source,
            trailingLimit: 1_000
        )) ?? []

        return lockBlocks.contains { block, trailing in
            let normalizedBlock = normalizedWhitespace(block)
            let normalizedTrailing = normalizedWhitespace(trailing)
            let checksActiveCandidate = normalizedBlock.contains("state.active?.id == candidateID")
                || (normalizedBlock.contains("state.active") && normalizedBlock.contains("candidateID"))
            let checksShutdown = normalizedBlock.contains("state.shuttingDown")
            let checksDeliveredFirstPacket = normalizedBlock.contains("state.deliveredFirstPacket")
            let setsTerminalError = normalizedBlock.contains("state.terminalError =")
            let capturesPending = normalizedBlock.contains("let pending = state.pending")
                || normalizedBlock.contains("pending = state.pending")
            let clearsPending = normalizedBlock.contains("state.pending = nil")
            let updatesPendingProbeCount = normalizedBlock.contains("setPendingContinuationCount(0)")
            let doesNotResumeInsideLock = !normalizedBlock.contains(".resume(")
                && !normalizedBlock.contains("resume(")
            let resumesPendingOutsideLock = normalizedTrailing.contains("pending?.resume(throwing:")
                || normalizedTrailing.contains(".resume(throwing:")
            let tiedToStartupTimeout = normalizedBlock.range(
                of: #"startup|Reliable packet startup timed out"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil || normalizedTrailing.range(
                of: #"startup|Reliable packet startup timed out"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil

            return checksActiveCandidate
                && checksShutdown
                && checksDeliveredFirstPacket
                && setsTerminalError
                && capturesPending
                && clearsPending
                && updatesPendingProbeCount
                && doesNotResumeInsideLock
                && resumesPendingOutsideLock
                && tiedToStartupTimeout
        }
    }

    private static func containsMessageSequenceMaximumBufferedMessages(in source: String) -> Bool {
        source.range(
            of: #"(?m)\b(?:public\s+|internal\s+)?static\s+(?:let|var)\s+messageSequenceMaximumBufferedMessages\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func messagePumpEnqueueUsesBoundedOverflowHandling(
        enqueue: String,
        messagePump: String
    ) -> Bool {
        let combined = enqueue + "\n" + messagePump
        let mentionsLimit = combined.contains("messageSequenceMaximumBufferedMessages")
        let checksQueueCount = enqueue.range(
            of: #"\b(?:state\.)?queue\.count\b"#,
            options: .regularExpression
        ) != nil
        let directOverflowHandling = enqueue.range(
            of: #"(?i)\b(?:overflow|bounded|drop|discard|evict|trim|removeFirst)\b"#,
            options: .regularExpression
        ) != nil
        let overflowHelperCall = enqueue.range(
            of: #"(?i)\b\w*(?:overflow|bounded|drop|discard|evict|trim)\w*\s*\("#,
            options: .regularExpression
        ) != nil

        return mentionsLimit && (overflowHelperCall || (checksQueueCount && directOverflowHandling))
    }

    private static func messagePumpEnqueueHasUnguardedNoWaiterAppend(_ enqueue: String) -> Bool {
        let normalized = normalizedWhitespace(enqueue)
        let directlyAppendsMessage = normalized.contains("state.queue.append(message)")
        let hasBoundedGuard = normalized.contains("messageSequenceMaximumBufferedMessages")
            || normalized.range(
                of: #"(?i)\b(?:overflow|bounded|drop|discard|evict|trim|removeFirst)\b"#,
                options: .regularExpression
            ) != nil
            || normalized.range(
                of: #"\b(?:state\.)?queue\.count\b"#,
                options: .regularExpression
            ) != nil

        return directlyAppendsMessage && !hasBoundedGuard
    }

    private static func pullPacketContainsZeroSizeContinueBranch(_ source: String) -> Bool {
        let zeroSizeGuardContinue = #"(?s)swift_gst_buffer_get_size\s*\([^)]*\)\s*>\s*0\s*else\s*\{[^}]*\bcontinue\b"#
        let zeroSizeIfContinue = #"(?s)swift_gst_buffer_get_size\s*\([^)]*\)\s*(?:==|<=)\s*0[^{]*\{[^}]*\bcontinue\b"#

        return source.range(of: zeroSizeGuardContinue, options: .regularExpression) != nil
            || source.range(of: zeroSizeIfContinue, options: .regularExpression) != nil
    }

    private static func nextPacketHasSkippedEmptyYieldAndTerminalChecks(_ source: String) -> Bool {
        let lowercased = source.lowercased()
        let mentionsSkippedEmptySample = lowercased.contains("empty")
            || lowercased.contains("zero")
            || lowercased.contains("skipped")
        let yieldsBeforeRetry = regexPatternsAppearInOrder(
            [
                #"await\s+Task\.yield\(\)"#,
                #"\bcontinue\b"#,
            ],
            in: source
        )

        guard let pullRange = source.range(of: "pullPacket(from: active)") else {
            return false
        }

        let beforePull = String(source[..<pullRange.lowerBound])
        let checksTerminalStateBeforePull = beforePull.contains("terminalError")
            || beforePull.contains("state.terminalError")
            || beforePull.contains("eos")
            || beforePull.contains("state.eos")
            || beforePull.contains("shuttingDown")
            || beforePull.contains("isCurrent(active)")
            || beforePull.range(
                of: #"(?i)\b(?:terminal|finished|completed)\w*\s*\("#,
                options: .regularExpression
            ) != nil

        return mentionsSkippedEmptySample
            && source.contains("await Task.yield()")
            && yieldsBeforeRetry
            && checksTerminalStateBeforePull
    }

    private static func containsWatchBackedContinuationQueue(in source: String) -> Bool {
        let normalized = normalizedWhitespace(source)
        let lowercased = normalized.lowercased()
        let hasContinuation = normalized.contains("CheckedContinuation<BusMessage?")
            || normalized.contains("UnsafeContinuation<BusMessage?")
            || lowercased.contains("continuation")
        let hasWaiters = lowercased.contains("waiter")
            || lowercased.contains("waiting")
        let hasFIFOQueue = lowercased.contains("queue")
            && normalized.contains(".append(")
            && (
                normalized.contains(".removeFirst()")
                    || normalized.contains(".removeFirst(")
                    || normalized.contains(".popFirst()")
                    || normalized.contains("Deque<")
            )

        return hasContinuation && hasWaiters && hasFIFOQueue
    }

    private static func containsRawGstMessagePointerStorage(in source: String) -> Bool {
        let storagePatterns = [
            #"(?m)\b(?:private|fileprivate|internal|public)?\s*(?:var|let)\s+\w+\s*:\s*\[\s*UnsafeMutablePointer\s*<\s*GstMessage\s*>\s*\]"#,
            #"(?m)\b(?:private|fileprivate|internal|public)?\s*(?:var|let)\s+\w+\s*:\s*Array\s*<\s*UnsafeMutablePointer\s*<\s*GstMessage\s*>\s*>"#,
            #"(?m)\b(?:private|fileprivate|internal|public)?\s*(?:var|let)\s+\w+\s*:\s*UnsafeMutablePointer\s*<\s*GstMessage\s*>\s*\?"#,
            #"(?i)\b(?:message|gstMessage)\w*Queue\b[^\n]*GstMessage"#,
        ]

        return storagePatterns.contains { pattern in
            source.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func messageSequenceDocsDescribeWatchBackedSemantics(_ source: String) -> Bool {
        let normalized = normalizedWhitespace(source).lowercased()
        let staleClaims = [
            "demand-driven bus polling",
            "bus is polled only when",
            "polls the gstreamer bus when the consumer requests next()",
            "each next() call must poll",
            "100 ms timed pop. current",
            "no continuation or detached producer exists on the messagesequence path",
            "continues to back the `errors()`, `warnings()`, `statechanges()`, and `waitforeos()`",
            "does not introduce a dropping bounded policy for bus messages",
            "do not add a dropping bounded policy",
            "does not add or standardize a new bounded buffer size",
            "no bounded dropping policy for bus messages",
            "default unbounded buffering policy",
            "does not silently drop yielded bus messages",
            "avoid introducing a swift-side dropping policy for bus control-plane messages",
        ]
        let hasWatchSemantics = normalized.contains("private gstreamer bus watch")
            || normalized.contains("private bus watch")
            || normalized.contains("watch-backed")
        let allowsBufferedBeforeNext = normalized.contains("before the consumer awaits next()")
            || normalized.contains("before next() is awaited")
            || normalized.contains("before `next()` is awaited")
        let describesBoundedBuffer = normalized.contains("bounded")
            && (
                normalized.contains("maximum buffered")
                    || normalized.contains("messagesequencemaximumbufferedmessages")
                    || normalized.contains("buffer limit")
                    || normalized.contains("buffer cap")
            )
        let describesOverflow = normalized.contains("overflow")
            || normalized.contains("drop oldest")
            || normalized.contains("drops oldest")
            || normalized.contains("evict oldest")
            || normalized.contains("evicts oldest")

        return hasWatchSemantics
            && allowsBufferedBeforeNext
            && describesBoundedBuffer
            && describesOverflow
            && staleClaims.allSatisfy { !normalized.contains($0) }
    }

    private static func containsPreviousCapsDestructionInsidePacketLock(in lockBodies: [String]) -> Bool {
        let destructivePatterns = [
            #"swift_gst_caps_unref\s*\("#,
            #"state\.previousCaps\s*=\s*swift_gst_caps_ref\s*\("#,
            #"state\.previousCaps\s*=\s*RetainedCaps\s*\("#,
            #"defer\s*\{[^}]*previousCaps[^}]*\}"#,
        ]

        return lockBodies.contains { body in
            destructivePatterns.contains { pattern in
                body.range(of: pattern, options: .regularExpression) != nil
            }
        }
    }

    private static func containsDiscontinuityRetryVersionPattern(
        packetState: String,
        detectDiscontinuity: String
    ) -> Bool {
        let tokenPattern = #"\b\w*(?:version|token|generation)\w*\b"#
        let stateHasToken = packetState.range(of: tokenPattern, options: [.regularExpression, .caseInsensitive]) != nil
        let functionUsesStateToken = detectDiscontinuity.range(
            of: #"state\.\w*(?:version|token|generation)\w*"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let hasRetryLoop = detectDiscontinuity.range(
            of: #"\bwhile\s+true\b|\brepeat\s*\{"#,
            options: .regularExpression
        ) != nil
        let canRetry = detectDiscontinuity.range(of: #"\bcontinue\b"#, options: .regularExpression) != nil
        let snapshotsRequiredState = [
            "previousCaps",
            "priorPTS",
            "priorDuration",
            "pendingDiscontinuity",
        ].allSatisfy { detectDiscontinuity.contains($0) }
        let comparesTokenBeforeCommit = detectDiscontinuity.split(separator: "\n").contains { line in
            let lowercasedLine = line.lowercased()
            let mentionsToken = lowercasedLine.contains("version")
                || lowercasedLine.contains("token")
                || lowercasedLine.contains("generation")
            return mentionsToken && (lowercasedLine.contains("==") || lowercasedLine.contains("!="))
        }

        return stateHasToken
            && functionUsesStateToken
            && hasRetryLoop
            && canRetry
            && snapshotsRequiredState
            && comparesTokenBeforeCommit
    }

    private static func containsBusMessagesNextSignature(in iterator: String) -> Bool {
        let normalized = normalizedWhitespace(iterator)
        let hasNonThrowingSignature = normalized.range(
            of: #"(?:public\s+)?(?:mutating\s+)?func\s+next\(\)\s+async\s*->\s*BusMessage\?"#,
            options: .regularExpression
        ) != nil
        let hasThrowingSignature = normalized.range(
            of: #"func\s+next\(\)\s+async\s+throws"#,
            options: .regularExpression
        ) != nil
        let hasNonisolatedExecutorMarker = normalized.contains("@concurrent")
            || normalized.contains("nonisolated")

        return hasNonThrowingSignature && !hasThrowingSignature && hasNonisolatedExecutorMarker
    }

    private static func containsWaitForEOSDeprecationMarker(in source: String) -> Bool {
        source.range(
            of: #"@available\s*\(\s*\*\s*,\s*deprecated\s*,\s*message:\s*"[^"]*waitForEOSOrError\(\)[^"]*"\s*\)\s*public\s+func\s+waitForEOS\(\)\s+async\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func waitForEOSDelegatesToThrowingHelperAndSwallowsErrors(_ implementation: String) -> Bool {
        let delegates = implementation.range(
            of: #"try\??\s+await\s+(?:self\.)?waitForEOSOrError\(\)"#,
            options: .regularExpression
        ) != nil
        let swallowsError = implementation.contains("try?") || implementation.range(
            of: #"\bcatch\b"#,
            options: .regularExpression
        ) != nil

        return delegates && swallowsError
    }

    private static func publicStaticMemberNames(in source: String) -> Set<String> {
        let pattern = #"\bpublic\s+static\s+(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let matches = regex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        return Set(matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[range])
        })
    }

    private static func containsExistingAllFilterDeclaration(in filter: String) -> Bool {
        let normalized = normalizedWhitespace(filter)
        let expected = """
        public static let all: Filter = [ .error, .warning, .info, .eos, .stateChanged, .element, .buffering, .durationChanged, .latency, .tag, .qos, .streamStart, .clockLost, .newClock, .progress ]
        """

        return normalized.contains(normalizedWhitespace(expected))
    }

    private static func containsStructConformance(
        typeName: String,
        genericClause: String,
        conformances: [String],
        in source: String
    ) -> Bool {
        guard let declarationLine = source
            .split(separator: "\n")
            .first(where: {
                $0.contains("public struct \(typeName)\(genericClause)")
            })
        else {
            return false
        }

        return conformances.allSatisfy { declarationLine.contains($0) }
    }

    private static func containsNestedIteratorConformance(in source: String) -> Bool {
        guard let reliablePackets = try? bracedDeclaration(beginningWith: "public struct ReliablePackets", in: source),
              let iteratorLine = reliablePackets
                .split(separator: "\n")
                .first(where: { $0.contains("struct AsyncIterator") || $0.contains("public struct AsyncIterator") })
        else {
            return false
        }

        return iteratorLine.contains("AsyncIteratorProtocol") && iteratorLine.contains("Sendable")
    }

    private static func containsReliableNextSignature(in source: String) -> Bool {
        guard let reliablePackets = try? bracedDeclaration(beginningWith: "public struct ReliablePackets", in: source),
              let iterator = try? bracedDeclaration(beginningWith: "public struct AsyncIterator", in: reliablePackets)
        else {
            return false
        }

        let normalized = iterator.replacingOccurrences(of: "\n", with: " ")
        let hasThrowingSignature = normalized.range(
            of: #"(?:mutating\s+)?func\s+next\(\)\s+async\s+throws\s*->\s*Element\?"#,
            options: .regularExpression
        ) != nil
        let hasConcurrentIsolation = normalized.contains("@concurrent")
            || normalized.contains("nonisolated")

        return hasThrowingSignature && hasConcurrentIsolation
    }

    private static func containsSendableType(_ typeName: String, in source: String) -> Bool {
        source.range(
            of: #"public\s+(?:struct|final\s+class|actor)\s+\#(typeName)\b[^\n{]*(?:@unchecked\s+)?Sendable"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsReliableDeliveryBuilderSignature(in source: String) -> Bool {
        guard let declaration = try? bracedDeclaration(
            beginningWith: "public func withReliableDelivery",
            in: source
        ) else {
            return false
        }

        let signatureSource = declaration.split(separator: "{", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? declaration
        let signature = signatureSource.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return signature.range(of: #"->\s*AudioSourceBuilder"#, options: .regularExpression) != nil
            && signature.range(
                of: #"leaky:\s*QueueLeaky\s*=\s*\.none"#,
                options: .regularExpression
            ) != nil
            && signature.range(
                of: #"maxBuffers:\s*(?:UInt|Int)\?\s*=\s*256"#,
                options: .regularExpression
            ) != nil
            && signature.range(
                of: #"maxBytes:\s*(?:UInt|Int)\?\s*=\s*nil"#,
                options: .regularExpression
            ) != nil
            && signature.range(
                of: #"maxTime:\s*Duration\?\s*=\s*\.seconds\(\s*2\s*\)"#,
                options: .regularExpression
            ) != nil
    }

    private static func containsReliablePacketDeclaration(in source: String) -> Bool {
        source.range(
            of: #"public\s+struct\s+ReliablePacket\s*<\s*Payload\s*:\s*Sendable\s*>\s*:\s*Sendable\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsDiscontinuityDeclarationWithExactKinds(in source: String) -> Bool {
        guard source.range(
            of: #"public\s+struct\s+Discontinuity\s*:\s*Sendable\b"#,
            options: .regularExpression
        ) != nil,
            let discontinuity = try? bracedDeclaration(beginningWith: "public struct Discontinuity", in: source),
            let kind = try? bracedDeclaration(beginningWith: "public enum Kind", in: discontinuity)
        else {
            return false
        }

        let cases = kind
            .split(separator: "\n")
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("case ") else { return [] }
                return trimmed
                    .dropFirst("case ".count)
                    .split(separator: ",")
                    .map { String($0.trimmingCharacters(in: .whitespaces)) }
                    .map { name in
                        if let paren = name.firstIndex(of: "(") {
                            return String(name[..<paren])
                        }
                        return name
                    }
            }

        let requiredFields = [
            "public let kind: Kind",
            "public let priorPTS: UInt64?",
            "public let priorDuration: UInt64?",
            "public let nextPTS: UInt64?",
            "public let duration: UInt64?",
            "public let droppedCount: Int?",
        ]

        return cases == ["formatChange", "discont", "gap", "dropped"]
            && kind.split(separator: "\n").first(where: { $0.contains("public enum Kind") })?.contains("Sendable") == true
            && requiredFields.allSatisfy { discontinuity.contains($0) }
            && discontinuity.range(of: #"public\s+var\s+pts\b"#, options: .regularExpression) == nil
    }

    private static func leadingDocumentationComment(for declaration: String, in source: String) throws -> String {
        guard let declarationRange = source.range(of: declaration) else {
            throw StaticAPISafetyError.declarationNotFound(declaration)
        }

        let prefix = source[..<declarationRange.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        var documentationLines: [String] = []

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                documentationLines.append(trimmed)
                continue
            }
            if trimmed.isEmpty && documentationLines.isEmpty {
                continue
            }
            break
        }

        return documentationLines.reversed().joined(separator: "\n")
    }

    private static func containsBufferingNewestPolicy(
        source: String,
        implementation: String,
        expectedCount: Int
    ) -> Bool {
        if implementation.contains(".bufferingNewest(\(expectedCount))") {
            return true
        }

        let newestArguments = bufferingNewestArguments(in: implementation)
        if newestArguments.contains(where: { sourceDefinesIntegerConstant($0, in: source, equalTo: expectedCount) }) {
            return true
        }

        let policyArguments = bufferingPolicyArguments(in: implementation)
        return policyArguments.contains { argument in
            sourceDefinesBufferingPolicyConstant(argument, in: source, newestCount: expectedCount)
        }
    }

    private static func bufferingNewestArguments(in source: String) -> [String] {
        arguments(after: ".bufferingNewest(", in: source)
    }

    private static func bufferingPolicyArguments(in source: String) -> [String] {
        arguments(after: "bufferingPolicy:", in: source)
            .map { argument in
                if let commaIndex = argument.firstIndex(of: ",") {
                    return String(argument[..<commaIndex])
                }
                return argument
            }
    }

    private static func arguments(after marker: String, in source: String) -> [String] {
        var arguments: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            if marker.hasSuffix("(") {
                var index = markerRange.upperBound
                let argumentStart = index
                var depth = 1

                while index < source.endIndex {
                    switch source[index] {
                    case "(":
                        depth += 1
                    case ")":
                        depth -= 1
                        if depth == 0 {
                            arguments.append(String(source[argumentStart..<index]))
                            searchStart = source.index(after: index)
                            break
                        }
                    default:
                        break
                    }
                    index = source.index(after: index)
                }

                if depth != 0 {
                    break
                }
            } else {
                var index = markerRange.upperBound
                while index < source.endIndex, source[index].isWhitespace {
                    index = source.index(after: index)
                }
                let argumentStart = index
                while index < source.endIndex, source[index] != ")" && source[index] != "\n" {
                    index = source.index(after: index)
                }
                arguments.append(String(source[argumentStart..<index]))
                searchStart = index
            }
        }

        return arguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func sourceDefinesIntegerConstant(_ expression: String, in source: String, equalTo value: Int) -> Bool {
        let names = candidateConstantNames(from: expression)
        return names.contains { name in
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"(?m)\b(?:public\s+|internal\s+|fileprivate\s+|private\s+|static\s+)*let\s+\#(escapedName)\b[^\n=]*=\s*\#(value)\b"#
            return source.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func sourceDefinesBufferingPolicyConstant(
        _ expression: String,
        in source: String,
        newestCount: Int
    ) -> Bool {
        let names = candidateConstantNames(from: expression)
        return names.contains { name in
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"(?m)\b(?:public\s+|internal\s+|fileprivate\s+|private\s+|static\s+)*let\s+\#(escapedName)\b[^\n=]*=[^\n]*\.bufferingNewest\(\s*\#(newestCount)\s*\)"#
            return source.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func candidateConstantNames(from expression: String) -> [String] {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedPrefixes = ["Self.", "AudioSource.", "AudioBufferSink.", "AudioPacketSink."]
            .reduce(into: trimmed) { result, prefix in
                if result.hasPrefix(prefix) {
                    result = String(result.dropFirst(prefix.count))
                }
            }
        var names = [trimmed, strippedPrefixes]

        if let lastComponent = trimmed.split(separator: ".").last {
            names.append(String(lastComponent))
        }

        return Array(Set(names)).filter { !$0.isEmpty }
    }
}

private enum StaticAPISafetyError: Error {
    case packageRootNotFound(String)
    case declarationNotFound(String)
    case unbalancedDeclaration(String)
}
