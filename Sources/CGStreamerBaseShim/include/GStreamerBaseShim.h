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
typedef void (*SwiftGstNativeSetBoolPropertyFunc)(
    void* instance_context,
    guint property_index,
    gboolean value
);
typedef void (*SwiftGstNativeSetIntPropertyFunc)(
    void* instance_context,
    guint property_index,
    gint value
);
typedef void (*SwiftGstNativeSetDoublePropertyFunc)(
    void* instance_context,
    guint property_index,
    gdouble value
);
typedef void (*SwiftGstNativeSetStringPropertyFunc)(
    void* instance_context,
    guint property_index,
    const gchar* value
);
typedef gboolean (*SwiftGstNativeGetBoolPropertyFunc)(
    void* instance_context,
    guint property_index
);
typedef gint (*SwiftGstNativeGetIntPropertyFunc)(
    void* instance_context,
    guint property_index
);
typedef gdouble (*SwiftGstNativeGetDoublePropertyFunc)(
    void* instance_context,
    guint property_index
);
typedef gchar* (*SwiftGstNativeGetStringPropertyFunc)(
    void* instance_context,
    guint property_index
);

typedef enum {
    SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL,
    SWIFT_GST_NATIVE_PROPERTY_KIND_INT,
    SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE,
    SWIFT_GST_NATIVE_PROPERTY_KIND_STRING,
    SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM,
} SwiftGstNativePropertyKind;

typedef struct {
    const gchar* name;
    const gchar* nick;
    const gchar* blurb;
} SwiftGstNativeEnumCaseDescriptor;

typedef struct {
    const gchar* name;
    const gchar* blurb;
    SwiftGstNativePropertyKind kind;
    gboolean bool_default;
    gint int_default;
    gint int_min;
    gint int_max;
    gdouble double_default;
    gdouble double_min;
    gdouble double_max;
    const gchar* string_default;
    const SwiftGstNativeEnumCaseDescriptor* enum_cases;
    guint enum_case_count;
} SwiftGstNativePropertyDescriptor;

typedef struct {
    const gchar* factory_name;
    const gchar* type_name;
    const gchar* klass;
    const gchar* long_name;
    const gchar* description;
    const gchar* author;
    guint rank;
    const gchar* sink_caps;
    const SwiftGstNativePropertyDescriptor* properties;
    guint property_count;
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
    const SwiftGstNativePropertyDescriptor* properties;
    guint property_count;
} SwiftGstBaseTransformInfo;

typedef struct {
    SwiftGstNativeCreateInstanceFunc create_instance;
    SwiftGstNativeDestroyInstanceFunc destroy_instance;
    SwiftGstBaseLifecycleFunc start;
    SwiftGstBaseLifecycleFunc stop;
    SwiftGstBaseSinkSetCapsFunc set_caps;
    SwiftGstBaseSinkRenderFunc render;
    SwiftGstNativeSetBoolPropertyFunc set_bool_property;
    SwiftGstNativeSetIntPropertyFunc set_int_property;
    SwiftGstNativeSetDoublePropertyFunc set_double_property;
    SwiftGstNativeSetStringPropertyFunc set_string_property;
    SwiftGstNativeGetBoolPropertyFunc get_bool_property;
    SwiftGstNativeGetIntPropertyFunc get_int_property;
    SwiftGstNativeGetDoublePropertyFunc get_double_property;
    SwiftGstNativeGetStringPropertyFunc get_string_property;
} SwiftGstBaseSinkCallbacks;

typedef struct {
    SwiftGstNativeCreateInstanceFunc create_instance;
    SwiftGstNativeDestroyInstanceFunc destroy_instance;
    SwiftGstBaseLifecycleFunc start;
    SwiftGstBaseLifecycleFunc stop;
    SwiftGstBaseTransformSetCapsFunc set_caps;
    SwiftGstBaseTransformIPFunc transform_ip;
    SwiftGstNativeSetBoolPropertyFunc set_bool_property;
    SwiftGstNativeSetIntPropertyFunc set_int_property;
    SwiftGstNativeSetDoublePropertyFunc set_double_property;
    SwiftGstNativeSetStringPropertyFunc set_string_property;
    SwiftGstNativeGetBoolPropertyFunc get_bool_property;
    SwiftGstNativeGetIntPropertyFunc get_int_property;
    SwiftGstNativeGetDoublePropertyFunc get_double_property;
    SwiftGstNativeGetStringPropertyFunc get_string_property;
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
