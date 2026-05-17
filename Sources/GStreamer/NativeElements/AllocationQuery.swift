import CGStreamer
import CGStreamerBaseShim
import CGStreamerShim

/// Snapshot of allocation parameters from a GStreamer allocation query.
public struct AllocationParams: Sendable {
    public var flags: UInt32
    public var align: Int
    public var prefix: Int
    public var padding: Int

    public init(flags: UInt32 = 0, align: Int = 0, prefix: Int = 0, padding: Int = 0) {
        self.flags = flags
        self.align = align
        self.prefix = prefix
        self.padding = padding
    }

    internal init(_ params: GstAllocationParams) {
        self.flags = UInt32(params.flags.rawValue)
        self.align = Int(params.align)
        self.prefix = Int(params.prefix)
        self.padding = Int(params.padding)
    }

    internal func withGstAllocationParams<R>(
        _ body: (UnsafePointer<GstAllocationParams>) throws -> R
    ) rethrows -> R? {
        guard align >= 0, prefix >= 0, padding >= 0 else {
            return nil
        }

        var params = GstAllocationParams()
        gst_allocation_params_init(&params)
        params.flags = GstMemoryFlags(rawValue: flags)
        params.align = gsize(align)
        params.prefix = gsize(prefix)
        params.padding = gsize(padding)
        return try withUnsafePointer(to: params, body)
    }
}

/// Snapshot of allocation metadata advertised by an allocation query.
public struct AllocationMetadata: Sendable {
    public var apiName: String
    public var paramsDescription: String?

    public init(apiName: String, paramsDescription: String? = nil) {
        self.apiName = apiName
        self.paramsDescription = paramsDescription
    }

    internal init(api: GType, params: UnsafePointer<GstStructure>?) {
        self.apiName = GLibString.borrow(swift_gst_g_type_name(api)) ?? ""
        self.paramsDescription = GLibString.takeOwnership(swift_gst_structure_to_string_nullable(params))
    }
}

public struct AllocationPoolConfiguration: Sendable {
    public var pool: AllocationPool?
    public var size: Int
    public var minimumBuffers: Int
    public var maximumBuffers: Int
}

/// Owned reference to a GStreamer buffer pool returned from an allocation query.
public final class AllocationPool: @unchecked Sendable {
    internal let pool: UnsafeMutablePointer<GstBufferPool>

    internal init(pool: UnsafeMutablePointer<GstBufferPool>) {
        self.pool = pool
    }

    deinit {
        swift_gst_object_unref(pool)
    }
}

/// Owned reference to a GStreamer allocator returned from an allocation query.
public final class BufferAllocator: @unchecked Sendable {
    internal let allocator: UnsafeMutablePointer<GstAllocator>

    internal init(allocator: UnsafeMutablePointer<GstAllocator>) {
        self.allocator = allocator
    }

    deinit {
        swift_gst_object_unref(allocator)
    }
}

public struct AllocationParamConfiguration: Sendable {
    public var allocator: BufferAllocator?
    public var params: AllocationParams
}

/// Borrowed allocation query wrapper scoped to a general-mode callback.
public struct AllocationQuery: ~Copyable {
    private let rawQuery: UnsafeMutablePointer<GstQuery>

    internal init(query: UnsafeMutablePointer<GstQuery>) {
        self.rawQuery = query
    }

    public var caps: Caps? {
        guard let caps = swift_gst_allocation_query_get_caps(rawQuery) else {
            return nil
        }
        return Caps(caps: caps, ownsReference: true)
    }

    public var needsPool: Bool {
        swift_gst_allocation_query_get_needs_pool(rawQuery) != 0
    }

    public var allocationPools: [AllocationPoolConfiguration] {
        (0..<Int(swift_gst_allocation_query_pool_count(rawQuery))).map { index in
            var size: guint = 0
            var minBuffers: guint = 0
            var maxBuffers: guint = 0
            let pool = swift_gst_allocation_query_pool_at(
                rawQuery,
                guint(index),
                &size,
                &minBuffers,
                &maxBuffers
            ).map { AllocationPool(pool: $0) }
            return AllocationPoolConfiguration(
                pool: pool,
                size: Int(size),
                minimumBuffers: Int(minBuffers),
                maximumBuffers: Int(maxBuffers)
            )
        }
    }

    public var allocationParams: [AllocationParamConfiguration] {
        (0..<Int(swift_gst_allocation_query_param_count(rawQuery))).map { index in
            var params = GstAllocationParams()
            gst_allocation_params_init(&params)
            let allocator = swift_gst_allocation_query_param_at(rawQuery, guint(index), &params)
                .map { BufferAllocator(allocator: $0) }
            return AllocationParamConfiguration(
                allocator: allocator,
                params: AllocationParams(params)
            )
        }
    }

    public var allocationMetadata: [AllocationMetadata] {
        (0..<Int(swift_gst_allocation_query_meta_count(rawQuery))).map { index in
            let api = swift_gst_allocation_query_meta_api_at(rawQuery, guint(index))
            return AllocationMetadata(
                apiName: GLibString.borrow(swift_gst_g_type_name(api)) ?? "",
                paramsDescription: GLibString.takeOwnership(
                    swift_gst_allocation_query_meta_params_string_at(rawQuery, guint(index))
                )
            )
        }
    }

    public func addPool(
        _ pool: AllocationPool?,
        size: Int,
        minimumBuffers: Int,
        maximumBuffers: Int
    ) {
        guard let gstSize = guint(exactly: size),
              let gstMinimumBuffers = guint(exactly: minimumBuffers),
              let gstMaximumBuffers = guint(exactly: maximumBuffers)
        else {
            return
        }

        swift_gst_allocation_query_add_pool(
            rawQuery,
            pool?.pool,
            gstSize,
            gstMinimumBuffers,
            gstMaximumBuffers
        )
    }

    public func addAllocationParam(_ allocator: BufferAllocator?, params: AllocationParams) {
        _ = params.withGstAllocationParams { gstParams in
            swift_gst_allocation_query_add_param(rawQuery, allocator?.allocator, gstParams)
        }
    }

    public func addAllocationMetadata(_ metadata: AllocationMetadata) {
        let type = g_type_from_name(metadata.apiName)
        guard type != 0 else {
            return
        }
        swift_gst_allocation_query_add_meta(rawQuery, type)
    }
}

/// Borrowed metadata wrapper scoped to a general-mode metadata callback.
public struct BufferMetadata: ~Copyable {
    private let rawMetadata: UnsafeMutablePointer<GstMeta>

    internal init(metadata: UnsafeMutablePointer<GstMeta>) {
        self.rawMetadata = metadata
    }

    public var apiName: String {
        GLibString.borrow(swift_gst_buffer_meta_api_name(rawMetadata)) ?? ""
    }

    public var implementationName: String {
        GLibString.borrow(swift_gst_buffer_meta_implementation_name(rawMetadata)) ?? ""
    }

    public var flags: UInt32 {
        UInt32(swift_gst_buffer_meta_flags(rawMetadata).rawValue)
    }
}
