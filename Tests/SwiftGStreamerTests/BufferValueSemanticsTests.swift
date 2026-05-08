import Testing
@testable import GStreamer

@Suite("Buffer Value Semantics Tests")
struct BufferValueSemanticsTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Copy mutation through mutable span leaves original bytes unchanged")
    func copyMutationThroughMutableSpanLeavesOriginalUnchanged() throws {
        let originalBytes: [UInt8] = [1, 2, 3, 4]
        let original = try Buffer(data: originalBytes)
        var copy = original

        try copy.mutableBytes.withUnsafeMutableBytes { bytes in
            try #require(bytes.count > 1)
            bytes[1] = 200
        }

        #expect(Self.bytes(in: original) == originalBytes)
        #expect(Self.bytes(in: copy) == [1, 200, 3, 4])
    }

    @Test("Copy mutation through unsafe mutable pointer leaves original bytes unchanged")
    func copyMutationThroughUnsafeMutableBytesLeavesOriginalUnchanged() throws {
        let originalBytes: [UInt8] = [5, 6, 7, 8]
        let original = try Buffer(data: originalBytes)
        var copy = original

        try copy.withUnsafeMutableBytes { bytes in
            try #require(bytes.count > 2)
            bytes[2] = 201
        }

        #expect(Self.bytes(in: original) == originalBytes)
        #expect(Self.bytes(in: copy) == [5, 6, 201, 8])
    }

    @Test("Empty data creates valid zero-size Buffer and preserves timestamps")
    func emptyDataCreatesValidZeroSizeBufferAndPreservesTimestamps() throws {
        let pts: UInt64 = 123_456_789
        let duration: UInt64 = 33_333_333

        let buffer = try Buffer(data: [], pts: pts, duration: duration)

        #expect(buffer.size == 0)
        #expect(buffer.bytes.byteCount == 0)
        #expect(buffer.pts == pts)
        #expect(buffer.duration == duration)
    }

    private static func bytes(in buffer: Buffer) -> [UInt8] {
        buffer.bytes.withUnsafeBytes { bytes in
            Array(bytes)
        }
    }
}
