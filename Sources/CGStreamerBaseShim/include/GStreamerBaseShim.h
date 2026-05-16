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
typedef gboolean (*SwiftGstStaticPluginInitFunc)(GstPlugin* plugin, gpointer user_data);
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
typedef GstFlowReturn (*SwiftGstBaseTransformFunc)(
    void* instance_context,
    GstBuffer* input_buffer,
    GstBuffer* output_buffer
);

typedef enum {
    SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
    SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
    SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
} SwiftGstBaseTransformHookStatus;

typedef struct {
    SwiftGstBaseTransformHookStatus status;
    GstCaps* caps;
} SwiftGstBaseTransformCapsResult;

typedef struct {
    SwiftGstBaseTransformHookStatus status;
    gsize size;
} SwiftGstBaseTransformSizeResult;

typedef struct {
    SwiftGstBaseTransformHookStatus status;
    gboolean value;
} SwiftGstBaseTransformBoolResult;

typedef SwiftGstBaseTransformCapsResult (*SwiftGstBaseTransformCapsFunc)(
    void* instance_context,
    GstPadDirection direction,
    GstCaps* caps,
    GstCaps* filter
);
typedef SwiftGstBaseTransformSizeResult (*SwiftGstBaseTransformGetUnitSizeFunc)(
    void* instance_context,
    GstCaps* caps
);
typedef SwiftGstBaseTransformSizeResult (*SwiftGstBaseTransformSizeFunc)(
    void* instance_context,
    GstPadDirection direction,
    GstCaps* caps,
    gsize size,
    GstCaps* other_caps
);
typedef SwiftGstBaseTransformBoolResult (*SwiftGstBaseTransformAllocationFunc)(
    void* instance_context,
    GstQuery* query
);
typedef SwiftGstBaseTransformBoolResult (*SwiftGstBaseTransformProposeAllocationFunc)(
    void* instance_context,
    GstQuery* decide_query,
    GstQuery* query
);
typedef SwiftGstBaseTransformBoolResult (*SwiftGstBaseTransformFilterMetaFunc)(
    void* instance_context,
    GstQuery* query,
    GType api,
    const GstStructure* params
);
typedef SwiftGstBaseTransformBoolResult (*SwiftGstBaseTransformCopyMetadataFunc)(
    void* instance_context,
    GstBuffer* input_buffer,
    GstBuffer* output_buffer
);
typedef SwiftGstBaseTransformBoolResult (*SwiftGstBaseTransformTransformMetadataFunc)(
    void* instance_context,
    GstBuffer* output_buffer,
    GstMeta* metadata,
    GstBuffer* input_buffer
);
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

typedef enum {
    SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE,
    SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE,
    SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE_GENERAL,
} SwiftGstBaseTransformMode;

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
    SwiftGstBaseTransformMode mode;
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
    SwiftGstBaseTransformFunc transform;
    SwiftGstBaseTransformCapsFunc transform_caps;
    SwiftGstBaseTransformCapsFunc fixate_caps;
    SwiftGstBaseTransformGetUnitSizeFunc get_unit_size;
    SwiftGstBaseTransformSizeFunc transform_size;
    SwiftGstBaseTransformAllocationFunc decide_allocation;
    SwiftGstBaseTransformProposeAllocationFunc propose_allocation;
    SwiftGstBaseTransformFilterMetaFunc filter_meta;
    SwiftGstBaseTransformCopyMetadataFunc copy_metadata;
    SwiftGstBaseTransformTransformMetadataFunc transform_meta;
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

gboolean swift_gst_register_base_sink_for_plugin(
    GstPlugin* plugin,
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

gboolean swift_gst_register_base_transform_for_plugin(
    GstPlugin* plugin,
    const SwiftGstBaseTransformInfo* info,
    const SwiftGstBaseTransformCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
);

gboolean swift_gst_register_static_plugin(
    const gchar* name,
    const gchar* description,
    const gchar* version,
    const gchar* license,
    const gchar* source,
    const gchar* package,
    const gchar* origin,
    SwiftGstStaticPluginInitFunc init_func,
    void* user_data,
    gchar** error_message
);

GstCaps* swift_gst_allocation_query_get_caps(GstQuery* query);
gboolean swift_gst_allocation_query_get_needs_pool(GstQuery* query);
guint swift_gst_allocation_query_pool_count(GstQuery* query);
GstBufferPool* swift_gst_allocation_query_pool_at(
    GstQuery* query,
    guint index,
    guint* size,
    guint* min_buffers,
    guint* max_buffers
);
void swift_gst_allocation_query_add_pool(
    GstQuery* query,
    GstBufferPool* pool,
    guint size,
    guint min_buffers,
    guint max_buffers
);
guint swift_gst_allocation_query_param_count(GstQuery* query);
GstAllocator* swift_gst_allocation_query_param_at(
    GstQuery* query,
    guint index,
    GstAllocationParams* params
);
void swift_gst_allocation_query_add_param(
    GstQuery* query,
    GstAllocator* allocator,
    const GstAllocationParams* params
);
guint swift_gst_allocation_query_meta_count(GstQuery* query);
GType swift_gst_allocation_query_meta_api_at(GstQuery* query, guint index);
gchar* swift_gst_allocation_query_meta_params_string_at(GstQuery* query, guint index);
void swift_gst_allocation_query_add_meta(GstQuery* query, GType api);
const gchar* swift_gst_g_type_name(GType type);
gchar* swift_gst_structure_to_string_nullable(const GstStructure* structure);
const gchar* swift_gst_buffer_meta_api_name(GstMeta* metadata);
const gchar* swift_gst_buffer_meta_implementation_name(GstMeta* metadata);
GstMetaFlags swift_gst_buffer_meta_flags(GstMeta* metadata);

#ifdef __cplusplus
}
#endif

#endif /* GSTREAMER_BASE_SHIM_H */
