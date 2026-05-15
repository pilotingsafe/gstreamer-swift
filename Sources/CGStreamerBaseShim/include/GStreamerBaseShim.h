#ifndef GSTREAMER_BASE_SHIM_H
#define GSTREAMER_BASE_SHIM_H

#include <gst/gst.h>
#include <gst/base/gstbasesink.h>
#include <gst/base/gstbasetransform.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*SwiftGstContextRetainFunc)(void* context);
typedef void (*SwiftGstContextReleaseFunc)(void* context);
typedef void* (*SwiftGstNativeCreateInstanceFunc)(void* class_context);
typedef void (*SwiftGstNativeDestroyInstanceFunc)(void* instance_context);
typedef gboolean (*SwiftGstBaseLifecycleFunc)(void* instance_context);
typedef gboolean (*SwiftGstBaseSinkSetCapsFunc)(void* instance_context, GstCaps* caps);
typedef GstFlowReturn (*SwiftGstBaseSinkRenderFunc)(void* instance_context, GstBuffer* buffer);
typedef gboolean (*SwiftGstBaseTransformSetCapsFunc)(
    void* instance_context,
    GstCaps* input_caps,
    GstCaps* output_caps
);
typedef GstFlowReturn (*SwiftGstBaseTransformIPFunc)(void* instance_context, GstBuffer* buffer);

typedef struct {
    const gchar* factory_name;
    const gchar* type_name;
    const gchar* klass;
    const gchar* long_name;
    const gchar* description;
    const gchar* author;
    guint rank;
    const gchar* sink_caps;
} SwiftGstBaseSinkInfo;

typedef struct {
    const gchar* factory_name;
    const gchar* type_name;
    const gchar* klass;
    const gchar* long_name;
    const gchar* description;
    const gchar* author;
    guint rank;
    const gchar* sink_caps;
    const gchar* src_caps;
    gboolean passthrough_on_same_caps;
    gboolean transform_ip_on_passthrough;
} SwiftGstBaseTransformInfo;

typedef struct {
    SwiftGstNativeCreateInstanceFunc create_instance;
    SwiftGstNativeDestroyInstanceFunc destroy_instance;
    SwiftGstBaseLifecycleFunc start;
    SwiftGstBaseLifecycleFunc stop;
    SwiftGstBaseSinkSetCapsFunc set_caps;
    SwiftGstBaseSinkRenderFunc render;
} SwiftGstBaseSinkCallbacks;

typedef struct {
    SwiftGstNativeCreateInstanceFunc create_instance;
    SwiftGstNativeDestroyInstanceFunc destroy_instance;
    SwiftGstBaseLifecycleFunc start;
    SwiftGstBaseLifecycleFunc stop;
    SwiftGstBaseTransformSetCapsFunc set_caps;
    SwiftGstBaseTransformIPFunc transform_ip;
} SwiftGstBaseTransformCallbacks;

gboolean swift_gst_register_base_sink(
    const SwiftGstBaseSinkInfo* info,
    const SwiftGstBaseSinkCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
);

gboolean swift_gst_register_base_transform(
    const SwiftGstBaseTransformInfo* info,
    const SwiftGstBaseTransformCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
);

#ifdef __cplusplus
}
#endif

#endif /* GSTREAMER_BASE_SHIM_H */
