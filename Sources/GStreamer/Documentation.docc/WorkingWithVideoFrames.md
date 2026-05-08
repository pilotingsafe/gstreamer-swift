# Working with Video Frames

Access and process raw video frame data safely with zero-copy read access.

## Overview

GStreamer for Swift provides safe, zero-copy read access to video frame data
through the ``VideoFrame`` type. Use ``VideoFrame/bytes`` for read-only
`RawSpan` access, or ``VideoFrame/withUnsafeBytes(_:)`` when an interop API
needs an unsafe pointer scoped to a closure.

Pulled video frames are read-only. If you need to mutate, modify, or write pixel
data, copy the frame bytes into `[UInt8]`, ``Buffer``, `CVPixelBuffer`, or
another mutable data structure and mutate that copy.

## Accessing Pixel Data

### Basic Frame Access

Use `withUnsafeBytes` when pointer lifetime should be explicit:

```swift
for await frame in sink.frames() {
    try frame.withUnsafeBytes { buffer in
        // buffer is UnsafeRawBufferPointer and is valid only in this closure.
        print("Buffer size: \(buffer.count) bytes")
    }
}
```

Use `bytes` when read-only `RawSpan` access is enough:

```swift
for await frame in sink.frames() {
    print("Frame bytes: \(frame.bytes.byteCount)")
}
```

### Processing BGRA Pixels

For BGRA format (common on macOS/iOS), pixels are arranged as Blue, Green, Red, Alpha:

```swift
try frame.withUnsafeBytes { buffer in
    for i in stride(from: 0, to: buffer.count, by: 4) {
        let b = buffer[i]     // Blue
        let g = buffer[i + 1] // Green
        let r = buffer[i + 2] // Red
        let a = buffer[i + 3] // Alpha

        // Process pixel...
    }
}
```

### Calculating Image Statistics

```swift
// Calculate average brightness
let brightness = try frame.withUnsafeBytes { buffer -> Int in
    var total = 0
    for i in stride(from: 0, to: buffer.count, by: 4) {
        // Weighted luminance: 0.299R + 0.587G + 0.114B
        total += Int(buffer[i + 2]) * 299 +
                 Int(buffer[i + 1]) * 587 +
                 Int(buffer[i]) * 114
    }
    return total / (buffer.count / 4) / 1000
}
print("Average brightness: \(brightness)")
```

## Mutating Frame Data

``VideoFrame`` does not expose mutable byte access. Copy into a mutable
destination before changing pixels:

```swift
let pixelData: [UInt8] = frame.bytes.withUnsafeBytes { bytes in
    Array(bytes)
}

var output = try Buffer(data: pixelData, pts: frame.pts, duration: frame.duration)
try output.withUnsafeMutableBytes { bytes in
    for i in stride(from: 0, to: bytes.count, by: 4) {
        bytes[i] = 255 - bytes[i]
        bytes[i + 1] = 255 - bytes[i + 1]
        bytes[i + 2] = 255 - bytes[i + 2]
    }
}
```

You can use the same copy-first approach with `[UInt8]`, `CVPixelBuffer`, or
another mutable structure that owns its storage.

## Integration with Vision Framework

Create a `CVPixelBuffer` copy for use with Vision or CoreML:

```swift
import Vision
import CoreVideo

let pixelBuffer = try frame.withUnsafeBytes { sourceBytes -> CVPixelBuffer in
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
        nil,
        frame.width,
        frame.height,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )

    guard let pixelBuffer else {
        throw GStreamerError.bufferMapFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let source = sourceBytes.baseAddress,
          let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw GStreamerError.bufferMapFailed
    }

    destination.copyMemory(
        from: source,
        byteCount: min(sourceBytes.count, CVPixelBufferGetDataSize(pixelBuffer))
    )
    return pixelBuffer
}

let requestHandler = VNImageRequestHandler(
    cvPixelBuffer: pixelBuffer,
    options: [:]
)

let request = VNDetectFaceRectanglesRequest()
try? requestHandler.perform([request])

if let results = request.results {
    print("Detected \(results.count) faces")
}
```

## Integration with Metal

Create a Metal texture from frame data:

```swift
import Metal

let device = MTLCreateSystemDefaultDevice()!

try frame.withUnsafeBytes { buffer in
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: frame.width,
        height: frame.height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]

    let texture = device.makeTexture(descriptor: descriptor)!

    texture.replace(
        region: MTLRegionMake2D(0, 0, frame.width, frame.height),
        mipmapLevel: 0,
        withBytes: buffer.baseAddress!,
        bytesPerRow: frame.width * 4
    )

    // Use texture for rendering...
}
```

## Memory Safety

The `RawSpan` returned by `bytes` is lifetime-bound to the expression where it is
accessed, and unsafe pointers from `withUnsafeBytes` cannot escape the closure.
This ensures the underlying GStreamer buffer remains valid while you access it:

```swift
// Correct: process data inside the closure.
try frame.withUnsafeBytes { buffer in
    processPixels(buffer)
}

// The buffer is automatically unmapped here.
```

If you need to keep the data, copy it while the frame is mapped:

```swift
let pixelData: [UInt8] = frame.bytes.withUnsafeBytes { bytes in
    Array(bytes)
}

// pixelData is a copy, safe to use after this expression.
```

## Handling Different Formats

Check the frame format before processing:

```swift
for await frame in sink.frames() {
    switch frame.format {
    case .bgra:
        // 4 bytes per pixel: BGRA
        try processBGRA(frame)

    case .rgba:
        // 4 bytes per pixel: RGBA
        try processRGBA(frame)

    case .nv12:
        // Y plane + UV plane (video decoder output)
        try processNV12(frame)

    case .gray8:
        // 1 byte per pixel (grayscale)
        try processGrayscale(frame)

    case .unknown(let format):
        print("Unknown format: \(format)")
    }
}
```

## Performance Tips

1. **Use the right format**: Request BGRA for Apple frameworks, NV12 for video codecs
2. **Avoid copies for read-only work**: Process data directly with `bytes` or `withUnsafeBytes`
3. **Copy before mutation**: Use ``Buffer`` or another mutable destination when writing pixels
4. **Batch processing**: Process multiple pixels per loop iteration
5. **Use SIMD**: Leverage Swift's SIMD types for parallel pixel operations

```swift
// Request specific format in pipeline
let pipeline = try Pipeline("""
    v4l2src ! videoconvert ! \
    video/x-raw,format=BGRA,width=1920,height=1080 ! \
    appsink name=sink
    """)
```
