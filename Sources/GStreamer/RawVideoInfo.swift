import CGStreamer
import CGStreamerShim

/// Structured information for `video/x-raw` caps.
public struct RawVideoInfo: Sendable {
    private let storage: Storage

    private final class Storage: @unchecked Sendable {
        let info: UnsafeMutablePointer<GstVideoInfo>

        init(info: UnsafeMutablePointer<GstVideoInfo>) {
            self.info = info
        }

        deinit {
            swift_gst_video_info_free(info)
        }
    }

    public init(caps: Caps) throws {
        guard let info = swift_gst_video_info_new_from_caps(caps.caps) else {
            throw GStreamerError.rawVideoInfoFailed(caps.description)
        }
        self.storage = Storage(info: info)
    }

    public var width: Int {
        Int(swift_gst_video_info_width(storage.info))
    }

    public var height: Int {
        Int(swift_gst_video_info_height(storage.info))
    }

    public var formatDescription: String {
        GLibString.borrow(swift_gst_video_info_format_name(storage.info)) ?? ""
    }

    public var byteSize: Int {
        Int(swift_gst_video_info_size(storage.info))
    }

    public func caps() -> Caps {
        guard let caps = swift_gst_video_info_to_caps_copy(storage.info) else {
            preconditionFailure("GStreamer failed to convert valid raw video info to caps")
        }
        return Caps(caps: caps, ownsReference: true)
    }
}
