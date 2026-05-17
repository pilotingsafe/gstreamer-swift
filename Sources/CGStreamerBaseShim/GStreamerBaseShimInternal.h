#ifndef GSTREAMER_BASE_SHIM_INTERNAL_H
#define GSTREAMER_BASE_SHIM_INTERNAL_H

#include "include/GStreamerBaseShim.h"

G_GNUC_INTERNAL
gboolean swift_gst_base_sink_fail(
    gchar** error_message,
    const gchar* format,
    ...
) G_GNUC_PRINTF(2, 3);

G_GNUC_INTERNAL
gboolean swift_gst_base_sink_is_non_empty(const gchar* value);

G_GNUC_INTERNAL
gboolean swift_gst_base_sink_is_valid_factory_name(const gchar* name);

G_GNUC_INTERNAL
gboolean swift_gst_base_sink_is_valid_type_name(const gchar* name);

G_GNUC_INTERNAL
void swift_gst_native_property_descriptors_free(
    SwiftGstNativePropertyDescriptor* properties,
    guint property_count
);

G_GNUC_INTERNAL
gboolean swift_gst_native_property_descriptors_copy(
    const SwiftGstNativePropertyDescriptor* source_properties,
    guint property_count,
    const gchar* registration_kind,
    SwiftGstNativePropertyDescriptor** copied_properties,
    gchar** error_message
);

G_GNUC_INTERNAL
void swift_gst_native_properties_install(
    GObjectClass* object_class,
    const SwiftGstNativePropertyDescriptor* properties,
    guint property_count,
    const gchar* registration_kind
);

G_GNUC_INTERNAL
void swift_gst_native_property_set(
    const gchar* registration_kind,
    GObject* object,
    guint property_id,
    const GValue* value,
    GParamSpec* param_spec,
    const SwiftGstNativePropertyDescriptor* properties,
    guint property_count,
    void* instance_context,
    SwiftGstNativeSetBoolPropertyFunc set_bool_property,
    SwiftGstNativeSetIntPropertyFunc set_int_property,
    SwiftGstNativeSetDoublePropertyFunc set_double_property,
    SwiftGstNativeSetStringPropertyFunc set_string_property
);

G_GNUC_INTERNAL
void swift_gst_native_property_get(
    GObject* object,
    guint property_id,
    GValue* value,
    GParamSpec* param_spec,
    const SwiftGstNativePropertyDescriptor* properties,
    guint property_count,
    void* instance_context,
    SwiftGstNativeGetBoolPropertyFunc get_bool_property,
    SwiftGstNativeGetIntPropertyFunc get_int_property,
    SwiftGstNativeGetDoublePropertyFunc get_double_property,
    SwiftGstNativeGetStringPropertyFunc get_string_property
);

#endif /* GSTREAMER_BASE_SHIM_INTERNAL_H */
