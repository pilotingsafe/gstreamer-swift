import CGStreamer
import CGStreamerShim

/// A borrowed GStreamer buffer valid only for the transform callback scope.
///
/// Raw pointers received through ``withUnsafeBytes(_:)`` or
/// ``withUnsafeMutableBytes(_:)`` must not escape the closure. Read-only access
/// is attempted with ``withUnsafeBytes(_:)``. Mutable access is available only
/// when GStreamer provides a writable buffer. Use ``retainedReference()`` or
/// ``deepCopy()`` when data must outlive the callback.
public struct MutableBorrowedBuffer: ~Copyable {
    private let buffer: UnsafeMutablePointer<GstBuffer>

    internal init(buffer: UnsafeMutablePointer<GstBuffer>) {
        self.buffer = buffer
    }

    /// The buffer size in bytes.
    public var size: Int {
        Int(swift_gst_buffer_get_size(buffer))
    }

    /// The presentation timestamp in nanoseconds, or nil when unset.
    public var pts: UInt64? {
        let value = swift_gst_buffer_get_pts(buffer)
        return swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
    }

    /// The buffer duration in nanoseconds, or nil when unset.
    public var duration: UInt64? {
        let value = swift_gst_buffer_get_duration(buffer)
        return swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
    }

    /// Maps the borrowed buffer for read access during the closure.
    ///
    /// The raw buffer pointer is invalid after the closure returns and must not
    /// be stored or used outside the closure.
    public func withUnsafeBytes<R>(
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        var mapInfo = GstMapInfo()
        guard swift_gst_buffer_map_read(buffer, &mapInfo) != 0 else {
            throw GStreamerError.bufferMapFailed
        }
        defer { swift_gst_buffer_unmap(buffer, &mapInfo) }

        let bytes = UnsafeRawBufferPointer(start: mapInfo.data, count: Int(mapInfo.size))
        return try body(bytes)
    }

    /// Maps the borrowed buffer for write access during the closure.
    ///
    /// Passthrough `transform_ip_on_passthrough` callbacks may receive a
    /// non-writable buffer. In that case, write mapping fails and this method
    /// throws ``GStreamerError/bufferMapFailed``.
    ///
    /// The raw buffer pointer is invalid after the closure returns and must not
    /// be stored or used outside the closure.
    public func withUnsafeMutableBytes<R>(
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        var mapInfo = GstMapInfo()
        guard swift_gst_buffer_map_write(buffer, &mapInfo) != 0 else {
            throw GStreamerError.bufferMapFailed
        }
        defer { swift_gst_buffer_unmap(buffer, &mapInfo) }

        let byteCount = Int(mapInfo.size)
        if byteCount == 0 {
            return try body(UnsafeMutableRawBufferPointer(start: nil, count: 0))
        }
        guard let data = mapInfo.data else {
            throw GStreamerError.bufferMapFailed
        }

        let bytes = UnsafeMutableRawBufferPointer(start: data, count: byteCount)
        return try body(bytes)
    }

    /// Returns an owned `Buffer` that retains the underlying `GstBuffer`.
    public func retainedReference() -> Buffer {
        _ = swift_gst_buffer_ref(buffer)
        return Buffer(buffer: buffer, ownsReference: true)
    }

    /// Returns an owned deep copy of the underlying `GstBuffer`.
    public func deepCopy() throws -> Buffer {
        guard let copied = gst_buffer_copy_deep(buffer) else {
            throw GStreamerError.bufferMapFailed
        }
        return Buffer(buffer: copied, ownsReference: true)
    }
}
