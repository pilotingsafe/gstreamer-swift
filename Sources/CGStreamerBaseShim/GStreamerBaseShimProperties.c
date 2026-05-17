#include "GStreamerBaseShimInternal.h"

#include <stdarg.h>

GstCaps* swift_gst_allocation_query_get_caps(GstQuery* query) {
    if (query == NULL) {
        return NULL;
    }

    GstCaps* caps = NULL;
    gst_query_parse_allocation(query, &caps, NULL);
    return caps != NULL ? gst_caps_ref(caps) : NULL;
}

gboolean swift_gst_allocation_query_get_needs_pool(GstQuery* query) {
    if (query == NULL) {
        return FALSE;
    }

    gboolean needs_pool = FALSE;
    gst_query_parse_allocation(query, NULL, &needs_pool);
    return needs_pool;
}

guint swift_gst_allocation_query_pool_count(GstQuery* query) {
    return query != NULL ? gst_query_get_n_allocation_pools(query) : 0;
}

GstBufferPool* swift_gst_allocation_query_pool_at(
    GstQuery* query,
    guint index,
    guint* size,
    guint* min_buffers,
    guint* max_buffers
) {
    if (query == NULL || index >= gst_query_get_n_allocation_pools(query)) {
        return NULL;
    }

    GstBufferPool* pool = NULL;
    gst_query_parse_nth_allocation_pool(query, index, &pool, size, min_buffers, max_buffers);
    return pool;
}

void swift_gst_allocation_query_add_pool(
    GstQuery* query,
    GstBufferPool* pool,
    guint size,
    guint min_buffers,
    guint max_buffers
) {
    if (query != NULL) {
        gst_query_add_allocation_pool(query, pool, size, min_buffers, max_buffers);
    }
}

guint swift_gst_allocation_query_param_count(GstQuery* query) {
    return query != NULL ? gst_query_get_n_allocation_params(query) : 0;
}

GstAllocator* swift_gst_allocation_query_param_at(
    GstQuery* query,
    guint index,
    GstAllocationParams* params
) {
    if (query == NULL || index >= gst_query_get_n_allocation_params(query)) {
        return NULL;
    }

    GstAllocator* allocator = NULL;
    gst_query_parse_nth_allocation_param(query, index, &allocator, params);
    return allocator;
}

void swift_gst_allocation_query_add_param(
    GstQuery* query,
    GstAllocator* allocator,
    const GstAllocationParams* params
) {
    if (query != NULL) {
        gst_query_add_allocation_param(query, allocator, params);
    }
}

guint swift_gst_allocation_query_meta_count(GstQuery* query) {
    return query != NULL ? gst_query_get_n_allocation_metas(query) : 0;
}

GType swift_gst_allocation_query_meta_api_at(GstQuery* query, guint index) {
    if (query == NULL || index >= gst_query_get_n_allocation_metas(query)) {
        return 0;
    }

    return gst_query_parse_nth_allocation_meta(query, index, NULL);
}

gchar* swift_gst_allocation_query_meta_params_string_at(GstQuery* query, guint index) {
    if (query == NULL || index >= gst_query_get_n_allocation_metas(query)) {
        return NULL;
    }

    const GstStructure* params = NULL;
    gst_query_parse_nth_allocation_meta(query, index, &params);
    return params != NULL ? gst_structure_to_string(params) : NULL;
}

void swift_gst_allocation_query_add_meta(GstQuery* query, GType api) {
    if (query != NULL && api != 0) {
        gst_query_add_allocation_meta(query, api, NULL);
    }
}

const gchar* swift_gst_g_type_name(GType type) {
    return type != 0 ? g_type_name(type) : NULL;
}

gchar* swift_gst_structure_to_string_nullable(const GstStructure* structure) {
    return structure != NULL ? gst_structure_to_string(structure) : NULL;
}

const gchar* swift_gst_buffer_meta_api_name(GstMeta* metadata) {
    return metadata != NULL && metadata->info != NULL
        ? g_type_name(metadata->info->api)
        : NULL;
}

const gchar* swift_gst_buffer_meta_implementation_name(GstMeta* metadata) {
    return metadata != NULL && metadata->info != NULL
        ? g_type_name(metadata->info->type)
        : NULL;
}

GstMetaFlags swift_gst_buffer_meta_flags(GstMeta* metadata) {
    return metadata != NULL ? metadata->flags : 0;
}

static gboolean swift_gst_native_property_fail(gchar** error_message, const gchar* format, ...) {
    if (error_message != NULL) {
        va_list args;
        va_start(args, format);
        *error_message = g_strdup_vprintf(format, args);
        va_end(args);
    }

    return FALSE;
}

static gboolean swift_gst_native_property_kind_is_valid(SwiftGstNativePropertyKind kind) {
    switch (kind) {
    case SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_INT:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM:
        return TRUE;
    }

    return FALSE;
}

static void swift_gst_native_enum_cases_free(
    const SwiftGstNativeEnumCaseDescriptor* enum_cases,
    guint enum_case_count
) {
    SwiftGstNativeEnumCaseDescriptor* mutable_cases =
        (SwiftGstNativeEnumCaseDescriptor*)enum_cases;
    if (mutable_cases == NULL) {
        return;
    }

    for (guint index = 0; index < enum_case_count; index++) {
        g_free((gpointer)mutable_cases[index].name);
        g_free((gpointer)mutable_cases[index].nick);
        g_free((gpointer)mutable_cases[index].blurb);
    }
    g_free(mutable_cases);
}

G_GNUC_INTERNAL void swift_gst_native_property_descriptors_free(
    SwiftGstNativePropertyDescriptor* properties,
    guint property_count
) {
    if (properties == NULL) {
        return;
    }

    for (guint index = 0; index < property_count; index++) {
        g_free((gpointer)properties[index].name);
        g_free((gpointer)properties[index].blurb);
        g_free((gpointer)properties[index].string_default);
        swift_gst_native_enum_cases_free(
            properties[index].enum_cases,
            properties[index].enum_case_count
        );
    }
    g_free(properties);
}

G_GNUC_INTERNAL gboolean swift_gst_native_property_descriptors_copy(
    const SwiftGstNativePropertyDescriptor* source_properties,
    guint property_count,
    const gchar* registration_kind,
    SwiftGstNativePropertyDescriptor** copied_properties,
    gchar** error_message
) {
    if (copied_properties == NULL) {
        return swift_gst_native_property_fail(
            error_message,
            "%s property descriptor destination is NULL",
            registration_kind
        );
    }
    *copied_properties = NULL;

    if (property_count == 0) {
        return TRUE;
    }
    if (source_properties == NULL) {
        return swift_gst_native_property_fail(
            error_message,
            "%s property descriptors are NULL",
            registration_kind
        );
    }
    if (property_count > G_MAXUINT - 1) {
        return swift_gst_native_property_fail(
            error_message,
            "%s property count is too large",
            registration_kind
        );
    }

    SwiftGstNativePropertyDescriptor* properties =
        g_new0(SwiftGstNativePropertyDescriptor, property_count);
    for (guint index = 0; index < property_count; index++) {
        const SwiftGstNativePropertyDescriptor* source = &source_properties[index];
        SwiftGstNativePropertyDescriptor* copy = &properties[index];

        if (!swift_gst_base_sink_is_non_empty(source->name)) {
            swift_gst_native_property_descriptors_free(properties, property_count);
            return swift_gst_native_property_fail(
                error_message,
                "%s property descriptor %u has an invalid name",
                registration_kind,
                index
            );
        }
        if (!swift_gst_native_property_kind_is_valid(source->kind)) {
            swift_gst_native_property_descriptors_free(properties, property_count);
            return swift_gst_native_property_fail(
                error_message,
                "%s property descriptor '%s' has an invalid kind",
                registration_kind,
                source->name
            );
        }
        if (source->enum_case_count > 0 && source->enum_cases == NULL) {
            swift_gst_native_property_descriptors_free(properties, property_count);
            return swift_gst_native_property_fail(
                error_message,
                "%s property descriptor '%s' has NULL enum cases",
                registration_kind,
                source->name
            );
        }

        copy->name = g_strdup(source->name);
        copy->blurb = g_strdup(source->blurb);
        copy->kind = source->kind;
        copy->bool_default = source->bool_default;
        copy->int_default = source->int_default;
        copy->int_min = source->int_min;
        copy->int_max = source->int_max;
        copy->double_default = source->double_default;
        copy->double_min = source->double_min;
        copy->double_max = source->double_max;
        copy->string_default = g_strdup(source->string_default);
        copy->enum_case_count = source->enum_case_count;

        if (source->enum_case_count == 0) {
            continue;
        }

        SwiftGstNativeEnumCaseDescriptor* enum_cases =
            g_new0(SwiftGstNativeEnumCaseDescriptor, source->enum_case_count);
        copy->enum_cases = enum_cases;
        for (guint case_index = 0; case_index < source->enum_case_count; case_index++) {
            const SwiftGstNativeEnumCaseDescriptor* source_case =
                &source->enum_cases[case_index];
            SwiftGstNativeEnumCaseDescriptor* copied_case = &enum_cases[case_index];

            if (!swift_gst_base_sink_is_non_empty(source_case->name)) {
                swift_gst_native_property_descriptors_free(properties, property_count);
                return swift_gst_native_property_fail(
                    error_message,
                    "%s property descriptor '%s' has an invalid enum case name",
                    registration_kind,
                    source->name
                );
            }

            copied_case->name = g_strdup(source_case->name);
            copied_case->nick = g_strdup(source_case->nick);
            copied_case->blurb = g_strdup(source_case->blurb);
        }
    }

    *copied_properties = properties;
    return TRUE;
}

static GParamSpec* swift_gst_native_property_param_spec(
    const SwiftGstNativePropertyDescriptor* descriptor
) {
    if (descriptor == NULL || descriptor->name == NULL) {
        return NULL;
    }

    const gchar* blurb = descriptor->blurb != NULL ? descriptor->blurb : descriptor->name;
    GParamFlags flags = (GParamFlags)(G_PARAM_READWRITE | GST_PARAM_MUTABLE_PLAYING);

    switch (descriptor->kind) {
    case SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL:
        return g_param_spec_boolean(
            descriptor->name,
            descriptor->name,
            blurb,
            descriptor->bool_default,
            flags
        );
    case SWIFT_GST_NATIVE_PROPERTY_KIND_INT:
        return g_param_spec_int(
            descriptor->name,
            descriptor->name,
            blurb,
            descriptor->int_min,
            descriptor->int_max,
            descriptor->int_default,
            flags
        );
    case SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE:
        return g_param_spec_double(
            descriptor->name,
            descriptor->name,
            blurb,
            descriptor->double_min,
            descriptor->double_max,
            descriptor->double_default,
            flags
        );
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM:
        return g_param_spec_string(
            descriptor->name,
            descriptor->name,
            blurb,
            descriptor->string_default,
            flags
        );
    }

    return NULL;
}

G_GNUC_INTERNAL void swift_gst_native_properties_install(
    GObjectClass* object_class,
    const SwiftGstNativePropertyDescriptor* properties,
    guint property_count,
    const gchar* registration_kind
) {
    if (object_class == NULL || properties == NULL || property_count == 0) {
        return;
    }

    for (guint index = 0; index < property_count; index++) {
        GParamSpec* param_spec = swift_gst_native_property_param_spec(&properties[index]);
        if (param_spec == NULL) {
            g_warning(
                "%s property '%s' could not create a GParamSpec",
                registration_kind,
                properties[index].name != NULL ? properties[index].name : "<unnamed>"
            );
            continue;
        }

        g_object_class_install_property(object_class, index + 1, param_spec);
    }
}

static const SwiftGstNativePropertyDescriptor* swift_gst_native_property_for_id(
    GObject* object,
    guint property_id,
    GParamSpec* param_spec,
    const SwiftGstNativePropertyDescriptor* properties,
    guint property_count,
    guint* property_index
) {
    if (property_id == 0 || property_id > property_count || properties == NULL) {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
        return NULL;
    }

    guint index = property_id - 1;
    if (property_index != NULL) {
        *property_index = index;
    }
    return &properties[index];
}

static void swift_gst_native_property_warn_missing_setter(
    const gchar* registration_kind,
    const SwiftGstNativePropertyDescriptor* descriptor
) {
    g_warning(
        "%s property '%s' set ignored because instance context or setter callback is missing",
        registration_kind,
        descriptor != NULL && descriptor->name != NULL ? descriptor->name : "<unnamed>"
    );
}

G_GNUC_INTERNAL void swift_gst_native_property_set(
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
) {
    guint property_index = 0;
    const SwiftGstNativePropertyDescriptor* descriptor =
        swift_gst_native_property_for_id(
            object,
            property_id,
            param_spec,
            properties,
            property_count,
            &property_index
        );
    if (descriptor == NULL) {
        return;
    }
    if (instance_context == NULL) {
        swift_gst_native_property_warn_missing_setter(registration_kind, descriptor);
        return;
    }

    switch (descriptor->kind) {
    case SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL:
        if (set_bool_property == NULL) {
            swift_gst_native_property_warn_missing_setter(registration_kind, descriptor);
            return;
        }
        set_bool_property(instance_context, property_index, g_value_get_boolean(value));
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_INT:
        if (set_int_property == NULL) {
            swift_gst_native_property_warn_missing_setter(registration_kind, descriptor);
            return;
        }
        set_int_property(instance_context, property_index, g_value_get_int(value));
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE:
        if (set_double_property == NULL) {
            swift_gst_native_property_warn_missing_setter(registration_kind, descriptor);
            return;
        }
        set_double_property(instance_context, property_index, g_value_get_double(value));
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM:
        if (set_string_property == NULL) {
            swift_gst_native_property_warn_missing_setter(registration_kind, descriptor);
            return;
        }
        set_string_property(instance_context, property_index, g_value_get_string(value));
        return;
    }

    G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
}

static void swift_gst_native_property_set_default_value(
    const SwiftGstNativePropertyDescriptor* descriptor,
    GValue* value
) {
    if (descriptor == NULL || value == NULL) {
        return;
    }

    switch (descriptor->kind) {
    case SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL:
        g_value_set_boolean(value, descriptor->bool_default);
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_INT:
        g_value_set_int(value, descriptor->int_default);
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE:
        g_value_set_double(value, descriptor->double_default);
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM:
        g_value_set_string(value, descriptor->string_default);
        return;
    }
}

G_GNUC_INTERNAL void swift_gst_native_property_get(
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
) {
    guint property_index = 0;
    const SwiftGstNativePropertyDescriptor* descriptor =
        swift_gst_native_property_for_id(
            object,
            property_id,
            param_spec,
            properties,
            property_count,
            &property_index
        );
    if (descriptor == NULL) {
        return;
    }

    switch (descriptor->kind) {
    case SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL:
        if (instance_context != NULL && get_bool_property != NULL) {
            g_value_set_boolean(value, get_bool_property(instance_context, property_index));
        } else {
            swift_gst_native_property_set_default_value(descriptor, value);
        }
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_INT:
        if (instance_context != NULL && get_int_property != NULL) {
            g_value_set_int(value, get_int_property(instance_context, property_index));
        } else {
            swift_gst_native_property_set_default_value(descriptor, value);
        }
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE:
        if (instance_context != NULL && get_double_property != NULL) {
            g_value_set_double(value, get_double_property(instance_context, property_index));
        } else {
            swift_gst_native_property_set_default_value(descriptor, value);
        }
        return;
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING:
    case SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM:
        if (instance_context != NULL && get_string_property != NULL) {
            g_value_take_string(value, get_string_property(instance_context, property_index));
        } else {
            swift_gst_native_property_set_default_value(descriptor, value);
        }
        return;
    }

    G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
}
