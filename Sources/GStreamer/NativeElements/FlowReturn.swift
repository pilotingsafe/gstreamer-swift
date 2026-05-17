import CGStreamer
import CGStreamerBaseShim

/// Flow return values for Swift-backed native element callbacks.
public enum FlowReturn: Sendable {
    case ok
    case error
    case notNegotiated
    case flushing
    case eos
    case dropped
    case custom(Int32)
}

extension FlowReturn {
    internal var gstFlowReturn: GstFlowReturn {
        switch self {
        case .ok:
            return GST_FLOW_OK
        case .error:
            return GST_FLOW_ERROR
        case .notNegotiated:
            return GST_FLOW_NOT_NEGOTIATED
        case .flushing:
            return GST_FLOW_FLUSHING
        case .eos:
            return GST_FLOW_EOS
        case .dropped:
            return GST_FLOW_CUSTOM_SUCCESS
        case .custom(let value):
            return GstFlowReturn(rawValue: value)
        }
    }

    internal var baseSinkRenderGstFlowReturn: GstFlowReturn {
        switch self {
        case .dropped:
            return swift_gst_base_sink_flow_dropped()
        default:
            return gstFlowReturn
        }
    }

    internal var baseTransformGstFlowReturn: GstFlowReturn {
        switch self {
        case .dropped:
            return swift_gst_base_transform_flow_dropped()
        default:
            return gstFlowReturn
        }
    }
}
