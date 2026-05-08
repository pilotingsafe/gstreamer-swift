import CGStreamer
import CGStreamerShim
import Synchronization

/// A GStreamer pad for connecting elements.
///
/// Pads are the connection points between elements. Data flows from source pads
/// to sink pads. Use pads for dynamic pipeline construction and tee splitting.
///
/// ## Overview
///
/// Pads come in two types:
/// - Static pads: Always present on an element (e.g., "sink", "src")
/// - Request pads: Created on demand (e.g., "src_%u" on tee)
///
/// Request pads retain the ``Element`` that created them until they are
/// explicitly released or the pad is deinitialized. This allows the pad to
/// release itself safely if the caller drops it without calling
/// ``Element/releasePad(_:)``.
///
/// ## Topics
///
/// ### Linking
///
/// - ``link(to:)``
/// - ``unlink(from:)``
///
/// ## Example
///
/// ```swift
/// // Get static pads
/// let srcPad = source.staticPad("src")!
/// let sinkPad = sink.staticPad("sink")!
///
/// // Link them
/// srcPad.link(to: sinkPad)
/// ```
///
/// ## Tee Example
///
/// ```swift
/// // Create a tee to split a stream
/// let tee = try Element.make(factory: "tee", name: "splitter")
/// pipeline.add(tee)
///
/// // Request pads for each branch
/// let branch1Pad = tee.requestPad("src_%u")!
/// let branch2Pad = tee.requestPad("src_%u")!
///
/// // Link to downstream elements
/// branch1Pad.link(to: queue1.staticPad("sink")!)
/// branch2Pad.link(to: queue2.staticPad("sink")!)
/// ```
public final class Pad: @unchecked Sendable {
    /// The underlying GstPad pointer.
    internal let pad: UnsafeMutablePointer<GstPad>

    /// Whether this is a request pad that needs to be released.
    private let isRequestPad: Bool

    private struct RequestPadState: Sendable {
        var owner: Element?
        var hasReleased: Bool
        var diagnostics: RequestPadReleaseDiagnostics
    }

    /// Synchronized request-pad release state.
    private let requestPadState: Mutex<RequestPadState>

    internal init(pad: UnsafeMutablePointer<GstPad>, isRequestPad: Bool = false, element: Element? = nil) {
        self.pad = pad
        self.isRequestPad = isRequestPad
        self.requestPadState = Mutex(
            RequestPadState(
                owner: isRequestPad ? element : nil,
                hasReleased: !isRequestPad,
                diagnostics: RequestPadReleaseDiagnostics()
            )
        )
    }

    deinit {
        releaseRequestPadIfNeeded()
        swift_gst_pad_unref(pad)
    }

    /// Release the request pad exactly once, if this pad was requested from an element.
    ///
    /// The owner is taken out of synchronized state before calling into
    /// GStreamer so concurrent callers cannot release the same request pad more
    /// than once.
    @discardableResult
    internal func releaseRequestPadIfNeeded() -> Bool {
        guard isRequestPad else { return false }

        let owner = requestPadState.withLock { state -> Element? in
            guard !state.hasReleased else { return nil }
            state.hasReleased = true
            let owner = state.owner
            state.owner = nil
            if owner != nil {
                state.diagnostics.recordReleaseCall()
            }
            return owner
        }

        guard let owner else { return false }
        swift_gst_element_release_request_pad(owner.element, pad)
        return true
    }

    internal var debugIsRequestPadReleased: Bool {
        requestPadState.withLock { $0.hasReleased }
    }

    internal var debugRequestReleaseCallCount: Int {
        debugRequestReleaseDiagnostics.releaseCallCount
    }

    internal var debugRequestReleaseDiagnostics: RequestPadReleaseDiagnostics {
        requestPadState.withLock { $0.diagnostics }
    }

    /// Link this pad to another pad.
    ///
    /// - Parameter other: The sink pad to link to.
    /// - Returns: `true` if linking succeeded.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let success = srcPad.link(to: sinkPad)
    /// if !success {
    ///     print("Failed to link pads")
    /// }
    /// ```
    @discardableResult
    public func link(to other: Pad) -> Bool {
        swift_gst_pad_link(pad, other.pad) != 0
    }

    /// Unlink this pad from another pad.
    ///
    /// - Parameter other: The pad to unlink from.
    /// - Returns: `true` if unlinking succeeded.
    @discardableResult
    public func unlink(from other: Pad) -> Bool {
        swift_gst_pad_unlink(pad, other.pad) != 0
    }

    // MARK: - Pad Properties

    /// The name of this pad.
    public var name: String {
        GLibString.takeOwnership(swift_gst_pad_get_name(pad)) ?? ""
    }

    /// The direction of this pad (source or sink).
    public var direction: Direction {
        let dir = gst_pad_get_direction(pad)
        switch dir {
        case GST_PAD_SRC: return .source
        case GST_PAD_SINK: return .sink
        default: return .unknown
        }
    }

    /// Pad direction.
    public enum Direction: Sendable {
        case source
        case sink
        case unknown
    }

    /// Whether this pad is currently linked.
    public var isLinked: Bool {
        gst_pad_is_linked(pad) != 0
    }

    /// The current caps of this pad.
    public var currentCaps: String? {
        guard let caps = gst_pad_get_current_caps(pad) else {
            return nil
        }
        defer { swift_gst_caps_unref(caps) }
        return GLibString.takeOwnership(swift_gst_caps_to_string(caps))
    }

    // MARK: - Pad Probes

    /// Type of pad probe.
    public struct ProbeType: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Probe buffers.
        public static let buffer = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_buffer().rawValue))
        /// Probe buffer lists.
        public static let bufferList = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_buffer_list().rawValue))
        /// Probe downstream events.
        public static let eventDownstream = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_event_downstream().rawValue))
        /// Probe upstream events.
        public static let eventUpstream = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_event_upstream().rawValue))
        /// Probe downstream queries.
        public static let queryDownstream = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_query_downstream().rawValue))
        /// Probe upstream queries.
        public static let queryUpstream = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_query_upstream().rawValue))
        /// Probe push operations.
        public static let push = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_push().rawValue))
        /// Probe pull operations.
        public static let pull = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_pull().rawValue))
        /// Block the pad.
        public static let blocking = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_blocking().rawValue))
        /// Idle probe (fires when pad is idle).
        public static let idle = ProbeType(rawValue: UInt32(swift_gst_pad_probe_type_idle().rawValue))

        /// Probe all data types.
        public static let allData: ProbeType = [.buffer, .bufferList, .eventDownstream, .eventUpstream]

        var gstType: GstPadProbeType {
            GstPadProbeType(rawValue: rawValue)
        }
    }

    /// Return value from a pad probe callback.
    public enum ProbeReturn: Sendable {
        /// Normal return, pass the data.
        case ok
        /// Drop the data.
        case drop
        /// Remove the probe.
        case remove
        /// Handled, don't pass.
        case handled
        /// Pass the data (same as ok).
        case pass
    }

    /// A handle to an installed pad probe.
    public struct ProbeHandle: Sendable {
        let id: gulong
    }

    private final class ProbeContext: @unchecked Sendable {
        let callback: @Sendable () -> ProbeReturn
        private let isCleanedUp = Mutex<Bool>(false)

        init(callback: @escaping @Sendable () -> ProbeReturn) {
            self.callback = callback
        }

        func markCleanedUp() -> Bool {
            isCleanedUp.withLock { cleanedUp in
                guard !cleanedUp else { return false }
                cleanedUp = true
                return true
            }
        }
    }

    internal static func mapProbeReturn(_ result: ProbeReturn) -> GstPadProbeReturn {
        switch result {
        case .ok: return GST_PAD_PROBE_OK
        case .drop: return GST_PAD_PROBE_DROP
        case .remove: return GST_PAD_PROBE_REMOVE
        case .handled: return GST_PAD_PROBE_HANDLED
        case .pass: return GST_PAD_PROBE_PASS
        }
    }

    private static func cleanupProbeContext(_ userData: UnsafeMutableRawPointer?) {
        guard let userData else { return }

        let unmanagedContext = Unmanaged<ProbeContext>.fromOpaque(userData)
        let context = unmanagedContext.takeUnretainedValue()
        if context.markCleanedUp() {
            unmanagedContext.release()
        }
    }

    /// Add a probe to this pad.
    ///
    /// Probes allow intercepting data flowing through a pad. Use them for
    /// debugging, monitoring, or modifying the data stream.
    ///
    /// - Parameters:
    ///   - type: The type of probe to install.
    ///   - callback: Called when data matching the probe type passes through.
    /// - Returns: A handle to remove the probe later.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let srcPad = element.staticPad("src")!
    ///
    /// // Monitor buffer flow
    /// let handle = srcPad.addProbe(type: .buffer) {
    ///     print("Buffer passed through!")
    ///     return .ok
    /// }
    ///
    /// // Later, remove the probe
    /// srcPad.removeProbe(handle)
    /// ```
    ///
    /// ## Blocking Probe
    ///
    /// ```swift
    /// // Block the pad until we're ready
    /// let blockHandle = srcPad.addProbe(type: [.buffer, .blocking]) {
    ///     print("Pad blocked")
    ///     return .ok
    /// }
    ///
    /// // Do some reconfiguration...
    ///
    /// // Unblock by removing the probe
    /// srcPad.removeProbe(blockHandle)
    /// ```
    @discardableResult
    public func addProbe(type: ProbeType, callback: @escaping @Sendable () -> ProbeReturn) -> ProbeHandle {
        let context = ProbeContext(callback: callback)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()

        // C callback that will be called by GStreamer
        let cCallback: GstPadProbeCallback = { _, _, userData -> GstPadProbeReturn in
            guard let userData = userData else { return GST_PAD_PROBE_OK }
            let context = Unmanaged<ProbeContext>.fromOpaque(userData).takeUnretainedValue()
            return Pad.mapProbeReturn(context.callback())
        }

        return withExtendedLifetime(context) {
            let probeId = gst_pad_add_probe(
                pad,
                type.gstType,
                cCallback,
                contextPointer,
                { userData in
                    Pad.cleanupProbeContext(userData)
                }
            )

            if probeId == 0 {
                Pad.cleanupProbeContext(contextPointer)
            }

            return ProbeHandle(id: probeId)
        }
    }

    /// Remove a previously installed probe.
    ///
    /// - Parameter handle: The handle returned from ``addProbe(type:callback:)``.
    public func removeProbe(_ handle: ProbeHandle) {
        guard handle.id != 0 else { return }
        gst_pad_remove_probe(pad, handle.id)
    }

    /// Add a blocking probe that fires once when idle.
    ///
    /// This is useful for dynamic pipeline reconfiguration.
    ///
    /// - Parameter callback: Called when the pad becomes idle.
    /// - Returns: A probe handle to remove if needed.
    @discardableResult
    public func addIdleProbe(callback: @escaping @Sendable () -> Void) -> ProbeHandle {
        addProbe(type: [.idle, .blocking]) {
            callback()
            return .remove  // One-shot probe
        }
    }
}

internal final class RequestPadReleaseDiagnostics: @unchecked Sendable {
    private let releaseCallCountStorage = Mutex<Int>(0)

    internal var releaseCallCount: Int {
        releaseCallCountStorage.withLock { $0 }
    }

    fileprivate func recordReleaseCall() {
        releaseCallCountStorage.withLock { $0 += 1 }
    }
}
