#include "include/GStreamerBaseShim.h"

#include <stdarg.h>
#include <string.h>

typedef struct {
    GstBaseSink parent_instance;
    void* instance_context;
} SwiftGstNativeBaseSink;

typedef struct {
    GstBaseSinkClass parent_class;
    struct SwiftGstBaseSinkRegistration* registration;
} SwiftGstNativeBaseSinkClass;

typedef struct SwiftGstBaseSinkRegistration {
    gchar* factory_name;
    gchar* type_name;
    gchar* klass;
    gchar* long_name;
    gchar* description;
    gchar* author;
    gchar* sink_caps;
    guint rank;
    SwiftGstNativePropertyDescriptor* properties;
    guint property_count;
    SwiftGstBaseSinkCallbacks callbacks;
    void* class_context;
    SwiftGstContextReleaseFunc release_class_context;
} SwiftGstBaseSinkRegistration;

typedef struct {
    GstBaseTransform parent_instance;
    void* instance_context;
} SwiftGstNativeBaseTransform;

typedef struct {
    GstBaseTransformClass parent_class;
    struct SwiftGstBaseTransformRegistration* registration;
} SwiftGstNativeBaseTransformClass;

typedef struct SwiftGstBaseTransformRegistration {
    gchar* factory_name;
    gchar* type_name;
    gchar* klass;
    gchar* long_name;
    gchar* description;
    gchar* author;
    gchar* sink_caps;
    gchar* src_caps;
    guint rank;
    SwiftGstBaseTransformMode mode;
    gboolean passthrough_on_same_caps;
    gboolean transform_ip_on_passthrough;
    SwiftGstNativePropertyDescriptor* properties;
    guint property_count;
    SwiftGstBaseTransformCallbacks callbacks;
    void* class_context;
    SwiftGstContextReleaseFunc release_class_context;
} SwiftGstBaseTransformRegistration;

static GMutex swift_gst_base_sink_registration_mutex;
static GMutex swift_gst_base_transform_registration_mutex;
static GMutex swift_gst_base_transform_allocator_mutex;

typedef GstBuffer* (*SwiftGstBaseTransformOutputAllocatorFunc)(GstBuffer* input, gsize size);

static SwiftGstBaseTransformOutputAllocatorFunc swift_gst_base_transform_output_allocator = NULL;

static GstBuffer* swift_gst_base_transform_default_output_allocator(GstBuffer* input, gsize size) {
    (void)input;
    return gst_buffer_new_allocate(NULL, size, NULL);
}

static GstBuffer* swift_gst_base_transform_allocate_output(GstBuffer* input, gsize size) {
    g_mutex_lock(&swift_gst_base_transform_allocator_mutex);
    SwiftGstBaseTransformOutputAllocatorFunc allocator =
        swift_gst_base_transform_output_allocator != NULL
            ? swift_gst_base_transform_output_allocator
            : swift_gst_base_transform_default_output_allocator;
    g_mutex_unlock(&swift_gst_base_transform_allocator_mutex);

    return allocator(input, size);
}

void swift_gst_base_transform_test_set_output_allocator(
    SwiftGstBaseTransformOutputAllocatorFunc allocator
) {
    g_mutex_lock(&swift_gst_base_transform_allocator_mutex);
    swift_gst_base_transform_output_allocator = allocator;
    g_mutex_unlock(&swift_gst_base_transform_allocator_mutex);
}

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

static gboolean swift_gst_base_sink_fail(gchar** error_message, const gchar* format, ...) {
    if (error_message != NULL) {
        va_list args;
        va_start(args, format);
        *error_message = g_strdup_vprintf(format, args);
        va_end(args);
    }

    return FALSE;
}

static gboolean swift_gst_base_sink_is_non_empty(const gchar* value);

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
) {
    if (error_message == NULL) {
        return FALSE;
    }
    *error_message = NULL;

    if (!swift_gst_base_sink_is_non_empty(name)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin name is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(description)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin description is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(version)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin version is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(license)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin license is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(source)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin source is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(package)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin package is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(origin)) {
        return swift_gst_base_sink_fail(error_message, "Static plugin origin is empty");
    }
    if (init_func == NULL) {
        return swift_gst_base_sink_fail(error_message, "Static plugin init callback is NULL");
    }

    gboolean success = gst_plugin_register_static_full(
        GST_VERSION_MAJOR,
        GST_VERSION_MINOR,
        name,
        description,
        init_func,
        version,
        license,
        source,
        package,
        origin,
        user_data
    );

    if (!success) {
        return swift_gst_base_sink_fail(
            error_message,
            "Static plugin '%s' could not be registered",
            name
        );
    }

    return TRUE;
}

static gboolean swift_gst_base_sink_is_non_empty(const gchar* value) {
    return value != NULL && value[0] != '\0';
}

static gboolean swift_gst_base_sink_is_valid_factory_name(const gchar* name) {
    if (!swift_gst_base_sink_is_non_empty(name) || !g_ascii_isalnum(name[0])) {
        return FALSE;
    }

    for (const gchar* cursor = name; *cursor != '\0'; cursor++) {
        if (!g_ascii_isalnum(*cursor) && *cursor != '_' && *cursor != '-') {
            return FALSE;
        }
    }

    return TRUE;
}

static gboolean swift_gst_base_sink_is_valid_type_name(const gchar* name) {
    if (!swift_gst_base_sink_is_non_empty(name) || !g_ascii_isalpha(name[0])) {
        return FALSE;
    }

    for (const gchar* cursor = name; *cursor != '\0'; cursor++) {
        if (!g_ascii_isalnum(*cursor) && *cursor != '_') {
            return FALSE;
        }
    }

    return TRUE;
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

static void swift_gst_native_property_descriptors_free(
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

static gboolean swift_gst_native_property_descriptors_copy(
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
            G_MININT,
            G_MAXINT,
            descriptor->int_default,
            flags
        );
    case SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE:
        return g_param_spec_double(
            descriptor->name,
            descriptor->name,
            blurb,
            -G_MAXDOUBLE,
            G_MAXDOUBLE,
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

static void swift_gst_native_properties_install(
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

static void swift_gst_native_property_set(
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

static void swift_gst_native_property_get(
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

static void swift_gst_base_sink_release_class_context(SwiftGstBaseSinkRegistration* registration) {
    if (registration == NULL) {
        return;
    }

    if (registration->class_context != NULL && registration->release_class_context != NULL) {
        registration->release_class_context(registration->class_context);
    }
    registration->class_context = NULL;
    registration->release_class_context = NULL;
}

static void swift_gst_base_sink_deactivate_registration(SwiftGstBaseSinkRegistration* registration) {
    if (registration == NULL) {
        return;
    }

    swift_gst_base_sink_release_class_context(registration);
    memset(&registration->callbacks, 0, sizeof(registration->callbacks));
}

static void swift_gst_base_sink_free_registration(SwiftGstBaseSinkRegistration* registration) {
    if (registration == NULL) {
        return;
    }

    swift_gst_base_sink_deactivate_registration(registration);
    g_free(registration->factory_name);
    g_free(registration->type_name);
    g_free(registration->klass);
    g_free(registration->long_name);
    g_free(registration->description);
    g_free(registration->author);
    g_free(registration->sink_caps);
    swift_gst_native_property_descriptors_free(
        registration->properties,
        registration->property_count
    );
    g_free(registration);
}

static SwiftGstBaseSinkRegistration* swift_gst_base_sink_class_registration(GstBaseSink* sink) {
    if (sink == NULL) {
        return NULL;
    }

    SwiftGstNativeBaseSinkClass* klass =
        (SwiftGstNativeBaseSinkClass*)G_OBJECT_GET_CLASS(sink);
    return klass != NULL ? klass->registration : NULL;
}

static void* swift_gst_base_sink_instance_context(GstBaseSink* sink) {
    if (sink == NULL) {
        return NULL;
    }

    return ((SwiftGstNativeBaseSink*)sink)->instance_context;
}

static void swift_gst_base_sink_set_property(
    GObject* object,
    guint property_id,
    const GValue* value,
    GParamSpec* param_spec
) {
    GstBaseSink* sink = GST_BASE_SINK(object);
    SwiftGstBaseSinkRegistration* registration = swift_gst_base_sink_class_registration(sink);
    if (registration == NULL) {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
        return;
    }

    swift_gst_native_property_set(
        "BaseSink",
        object,
        property_id,
        value,
        param_spec,
        registration->properties,
        registration->property_count,
        swift_gst_base_sink_instance_context(sink),
        registration->callbacks.set_bool_property,
        registration->callbacks.set_int_property,
        registration->callbacks.set_double_property,
        registration->callbacks.set_string_property
    );
}

static void swift_gst_base_sink_get_property(
    GObject* object,
    guint property_id,
    GValue* value,
    GParamSpec* param_spec
) {
    GstBaseSink* sink = GST_BASE_SINK(object);
    SwiftGstBaseSinkRegistration* registration = swift_gst_base_sink_class_registration(sink);
    if (registration == NULL) {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
        return;
    }

    swift_gst_native_property_get(
        object,
        property_id,
        value,
        param_spec,
        registration->properties,
        registration->property_count,
        swift_gst_base_sink_instance_context(sink),
        registration->callbacks.get_bool_property,
        registration->callbacks.get_int_property,
        registration->callbacks.get_double_property,
        registration->callbacks.get_string_property
    );
}

static gboolean swift_gst_base_sink_start(GstBaseSink* sink) {
    void* instance_context = swift_gst_base_sink_instance_context(sink);
    if (instance_context == NULL) {
        return FALSE;
    }

    SwiftGstBaseSinkRegistration* registration = swift_gst_base_sink_class_registration(sink);
    if (registration == NULL || registration->callbacks.start == NULL) {
        return FALSE;
    }

    return registration->callbacks.start(instance_context);
}

static gboolean swift_gst_base_sink_stop(GstBaseSink* sink) {
    void* instance_context = swift_gst_base_sink_instance_context(sink);
    if (instance_context == NULL) {
        return TRUE;
    }

    SwiftGstBaseSinkRegistration* registration = swift_gst_base_sink_class_registration(sink);
    if (registration == NULL || registration->callbacks.stop == NULL) {
        return TRUE;
    }

    return registration->callbacks.stop(instance_context);
}

static gboolean swift_gst_base_sink_set_caps(GstBaseSink* sink, GstCaps* caps) {
    void* instance_context = swift_gst_base_sink_instance_context(sink);
    if (instance_context == NULL) {
        return FALSE;
    }

    SwiftGstBaseSinkRegistration* registration = swift_gst_base_sink_class_registration(sink);
    if (registration == NULL || registration->callbacks.set_caps == NULL) {
        return FALSE;
    }

    return registration->callbacks.set_caps(instance_context, caps);
}

static GstFlowReturn swift_gst_base_sink_render(GstBaseSink* sink, GstBuffer* buffer) {
    void* instance_context = swift_gst_base_sink_instance_context(sink);
    if (instance_context == NULL) {
        return GST_FLOW_ERROR;
    }

    SwiftGstBaseSinkRegistration* registration = swift_gst_base_sink_class_registration(sink);
    if (registration == NULL || registration->callbacks.render == NULL) {
        return GST_FLOW_ERROR;
    }

    return registration->callbacks.render(instance_context, buffer);
}

static void swift_gst_base_sink_finalize(GObject* object) {
    SwiftGstNativeBaseSink* sink = (SwiftGstNativeBaseSink*)object;
    SwiftGstBaseSinkRegistration* registration =
        swift_gst_base_sink_class_registration(GST_BASE_SINK(object));

    if (sink->instance_context != NULL) {
        void* instance_context = sink->instance_context;
        sink->instance_context = NULL;

        if (registration != NULL && registration->callbacks.destroy_instance != NULL) {
            registration->callbacks.destroy_instance(instance_context);
        }
    }

    GObjectClass* parent_class = G_OBJECT_CLASS(
        g_type_class_peek_parent(G_OBJECT_GET_CLASS(object))
    );
    if (parent_class != NULL && parent_class->finalize != NULL) {
        parent_class->finalize(object);
    }
}

static void swift_gst_base_sink_class_init(gpointer g_class, gpointer class_data) {
    SwiftGstNativeBaseSinkClass* native_class = (SwiftGstNativeBaseSinkClass*)g_class;
    SwiftGstBaseSinkRegistration* registration = (SwiftGstBaseSinkRegistration*)class_data;
    native_class->registration = registration;

    GObjectClass* object_class = G_OBJECT_CLASS(g_class);
    object_class->finalize = swift_gst_base_sink_finalize;
    if (registration != NULL && registration->property_count > 0) {
        object_class->set_property = swift_gst_base_sink_set_property;
        object_class->get_property = swift_gst_base_sink_get_property;
        swift_gst_native_properties_install(
            object_class,
            registration->properties,
            registration->property_count,
            "BaseSink"
        );
    }

    GstBaseSinkClass* sink_class = GST_BASE_SINK_CLASS(g_class);
    sink_class->start = swift_gst_base_sink_start;
    sink_class->stop = swift_gst_base_sink_stop;
    sink_class->set_caps = swift_gst_base_sink_set_caps;
    sink_class->render = swift_gst_base_sink_render;

    if (registration == NULL) {
        return;
    }

    GstElementClass* element_class = GST_ELEMENT_CLASS(g_class);
    gst_element_class_set_static_metadata(
        element_class,
        registration->long_name,
        registration->klass,
        registration->description,
        registration->author
    );

    GstCaps* caps = gst_caps_from_string(registration->sink_caps);
    if (caps == NULL) {
        return;
    }

    GstPadTemplate* pad_template = gst_pad_template_new(
        "sink",
        GST_PAD_SINK,
        GST_PAD_ALWAYS,
        caps
    );
    gst_caps_unref(caps);

    if (pad_template != NULL) {
        gst_element_class_add_pad_template(element_class, pad_template);
    }
}

static void swift_gst_base_sink_instance_init(GTypeInstance* instance, gpointer g_class) {
    SwiftGstNativeBaseSink* sink = (SwiftGstNativeBaseSink*)instance;
    SwiftGstNativeBaseSinkClass* klass = (SwiftGstNativeBaseSinkClass*)g_class;
    SwiftGstBaseSinkRegistration* registration = klass != NULL ? klass->registration : NULL;

    gst_base_sink_set_sync(GST_BASE_SINK(instance), FALSE);
    sink->instance_context = NULL;
    if (registration == NULL
        || registration->class_context == NULL
        || registration->callbacks.create_instance == NULL) {
        return;
    }

    sink->instance_context = registration->callbacks.create_instance(registration->class_context);
}

static gboolean swift_gst_base_sink_validate_info(
    const SwiftGstBaseSinkInfo* info,
    const SwiftGstBaseSinkCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    if (info == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink registration info is NULL");
    }
    if (callbacks == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink registration callbacks are NULL");
    }
    if (class_context == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink class context is NULL");
    }
    if (retain_class_context == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink class context retain callback is NULL");
    }
    if (release_class_context == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink class context release callback is NULL");
    }
    if (!swift_gst_base_sink_is_valid_factory_name(info->factory_name)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink factory name is invalid");
    }
    if (!swift_gst_base_sink_is_valid_type_name(info->type_name)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink GType name is invalid");
    }
    if (!swift_gst_base_sink_is_non_empty(info->klass)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink metadata klass is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->long_name)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink metadata long name is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->description)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink metadata description is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->author)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink metadata author is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->sink_caps)) {
        return swift_gst_base_sink_fail(error_message, "BaseSink sink caps are empty");
    }
    if (callbacks->destroy_instance == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink destroy_instance callback is NULL");
    }
    if (callbacks->start == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink start callback is NULL");
    }
    if (callbacks->stop == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink stop callback is NULL");
    }
    if (callbacks->set_caps == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink set_caps callback is NULL");
    }
    if (callbacks->render == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink render callback is NULL");
    }

    GstCaps* caps = gst_caps_from_string(info->sink_caps);
    if (caps == NULL) {
        return swift_gst_base_sink_fail(error_message, "BaseSink sink caps could not be parsed");
    }

    gboolean valid_caps = !gst_caps_is_empty(caps);
    gst_caps_unref(caps);
    if (!valid_caps) {
        return swift_gst_base_sink_fail(error_message, "BaseSink sink caps are empty");
    }

    return TRUE;
}

static gboolean swift_gst_register_base_sink_with_plugin(
    GstPlugin* plugin,
    const SwiftGstBaseSinkInfo* info,
    const SwiftGstBaseSinkCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    if (error_message == NULL) {
        return FALSE;
    }
    *error_message = NULL;

    if (!swift_gst_base_sink_validate_info(
        info,
        callbacks,
        class_context,
        retain_class_context,
        release_class_context,
        error_message
    )) {
        return FALSE;
    }

    SwiftGstBaseSinkRegistration* registration = g_new0(SwiftGstBaseSinkRegistration, 1);
    registration->factory_name = g_strdup(info->factory_name);
    registration->type_name = g_strdup(info->type_name);
    registration->klass = g_strdup(info->klass);
    registration->long_name = g_strdup(info->long_name);
    registration->description = g_strdup(info->description);
    registration->author = g_strdup(info->author);
    registration->sink_caps = g_strdup(info->sink_caps);
    registration->rank = info->rank;
    registration->property_count = info->property_count;
    if (!swift_gst_native_property_descriptors_copy(
        info->properties,
        info->property_count,
        "BaseSink",
        &registration->properties,
        error_message
    )) {
        swift_gst_base_sink_free_registration(registration);
        return FALSE;
    }
    registration->callbacks = *callbacks;
    registration->release_class_context = release_class_context;

    retain_class_context(class_context);
    registration->class_context = class_context;

    gboolean success = FALSE;
    gboolean type_registered = FALSE;

    g_mutex_lock(&swift_gst_base_sink_registration_mutex);

    if (g_type_from_name(registration->type_name) != 0) {
        g_mutex_unlock(&swift_gst_base_sink_registration_mutex);
        swift_gst_base_sink_free_registration(registration);
        return swift_gst_base_sink_fail(
            error_message,
            "BaseSink GType '%s' is already registered",
            info->type_name
        );
    }

    GstElementFactory* existing_factory = gst_element_factory_find(registration->factory_name);
    if (existing_factory != NULL) {
        gst_object_unref(existing_factory);
        g_mutex_unlock(&swift_gst_base_sink_registration_mutex);
        swift_gst_base_sink_free_registration(registration);
        return swift_gst_base_sink_fail(
            error_message,
            "BaseSink factory '%s' is already registered",
            info->factory_name
        );
    }

    GTypeInfo type_info = {
        .class_size = sizeof(SwiftGstNativeBaseSinkClass),
        .base_init = NULL,
        .base_finalize = NULL,
        .class_init = swift_gst_base_sink_class_init,
        .class_finalize = NULL,
        .class_data = registration,
        .instance_size = sizeof(SwiftGstNativeBaseSink),
        .n_preallocs = 0,
        .instance_init = swift_gst_base_sink_instance_init,
        .value_table = NULL,
    };

    GType type = g_type_register_static(
        GST_TYPE_BASE_SINK,
        registration->type_name,
        &type_info,
        0
    );
    if (type == 0) {
        g_mutex_unlock(&swift_gst_base_sink_registration_mutex);
        swift_gst_base_sink_free_registration(registration);
        return swift_gst_base_sink_fail(
            error_message,
            "BaseSink GType '%s' could not be registered",
            info->type_name
        );
    }
    type_registered = TRUE;

    success = gst_element_register(plugin, registration->factory_name, registration->rank, type);

    g_mutex_unlock(&swift_gst_base_sink_registration_mutex);

    if (!success) {
        if (type_registered) {
            swift_gst_base_sink_deactivate_registration(registration);
        } else {
            swift_gst_base_sink_free_registration(registration);
        }
        return swift_gst_base_sink_fail(
            error_message,
            "BaseSink factory '%s' could not be registered",
            info->factory_name
        );
    }

    *error_message = NULL;
    return TRUE;
}

gboolean swift_gst_register_base_sink(
    const SwiftGstBaseSinkInfo* info,
    const SwiftGstBaseSinkCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    return swift_gst_register_base_sink_with_plugin(
        NULL,
        info,
        callbacks,
        class_context,
        retain_class_context,
        release_class_context,
        error_message
    );
}

gboolean swift_gst_register_base_sink_for_plugin(
    GstPlugin* plugin,
    const SwiftGstBaseSinkInfo* info,
    const SwiftGstBaseSinkCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    if (error_message == NULL) {
        return FALSE;
    }
    *error_message = NULL;
    if (plugin == NULL) {
        return swift_gst_base_sink_fail(error_message, "Static plugin BaseSink plugin is NULL");
    }
    return swift_gst_register_base_sink_with_plugin(
        plugin,
        info,
        callbacks,
        class_context,
        retain_class_context,
        release_class_context,
        error_message
    );
}

static gboolean swift_gst_base_transform_fail(gchar** error_message, const gchar* format, ...) {
    if (error_message != NULL) {
        va_list args;
        va_start(args, format);
        *error_message = g_strdup_vprintf(format, args);
        va_end(args);
    }

    return FALSE;
}

static void swift_gst_base_transform_release_class_context(
    SwiftGstBaseTransformRegistration* registration
) {
    if (registration == NULL) {
        return;
    }

    if (registration->class_context != NULL && registration->release_class_context != NULL) {
        registration->release_class_context(registration->class_context);
    }
    registration->class_context = NULL;
    registration->release_class_context = NULL;
}

static void swift_gst_base_transform_deactivate_registration(
    SwiftGstBaseTransformRegistration* registration
) {
    if (registration == NULL) {
        return;
    }

    swift_gst_base_transform_release_class_context(registration);
    memset(&registration->callbacks, 0, sizeof(registration->callbacks));
}

static void swift_gst_base_transform_free_registration(
    SwiftGstBaseTransformRegistration* registration
) {
    if (registration == NULL) {
        return;
    }

    swift_gst_base_transform_deactivate_registration(registration);
    g_free(registration->factory_name);
    g_free(registration->type_name);
    g_free(registration->klass);
    g_free(registration->long_name);
    g_free(registration->description);
    g_free(registration->author);
    g_free(registration->sink_caps);
    g_free(registration->src_caps);
    swift_gst_native_property_descriptors_free(
        registration->properties,
        registration->property_count
    );
    g_free(registration);
}

static SwiftGstBaseTransformRegistration* swift_gst_base_transform_class_registration(
    GstBaseTransform* transform
) {
    if (transform == NULL) {
        return NULL;
    }

    SwiftGstNativeBaseTransformClass* klass =
        (SwiftGstNativeBaseTransformClass*)G_OBJECT_GET_CLASS(transform);
    return klass != NULL ? klass->registration : NULL;
}

static void* swift_gst_base_transform_instance_context(GstBaseTransform* transform) {
    if (transform == NULL) {
        return NULL;
    }

    return ((SwiftGstNativeBaseTransform*)transform)->instance_context;
}

static void swift_gst_base_transform_set_property(
    GObject* object,
    guint property_id,
    const GValue* value,
    GParamSpec* param_spec
) {
    GstBaseTransform* transform = GST_BASE_TRANSFORM(object);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL) {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
        return;
    }

    swift_gst_native_property_set(
        "BaseTransform",
        object,
        property_id,
        value,
        param_spec,
        registration->properties,
        registration->property_count,
        swift_gst_base_transform_instance_context(transform),
        registration->callbacks.set_bool_property,
        registration->callbacks.set_int_property,
        registration->callbacks.set_double_property,
        registration->callbacks.set_string_property
    );
}

static void swift_gst_base_transform_get_property(
    GObject* object,
    guint property_id,
    GValue* value,
    GParamSpec* param_spec
) {
    GstBaseTransform* transform = GST_BASE_TRANSFORM(object);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL) {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, param_spec);
        return;
    }

    swift_gst_native_property_get(
        object,
        property_id,
        value,
        param_spec,
        registration->properties,
        registration->property_count,
        swift_gst_base_transform_instance_context(transform),
        registration->callbacks.get_bool_property,
        registration->callbacks.get_int_property,
        registration->callbacks.get_double_property,
        registration->callbacks.get_string_property
    );
}

static gboolean swift_gst_base_transform_start(GstBaseTransform* transform) {
    void* instance_context = swift_gst_base_transform_instance_context(transform);
    if (instance_context == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL || registration->callbacks.start == NULL) {
        return FALSE;
    }

    return registration->callbacks.start(instance_context);
}

static gboolean swift_gst_base_transform_stop(GstBaseTransform* transform) {
    void* instance_context = swift_gst_base_transform_instance_context(transform);
    if (instance_context == NULL) {
        return TRUE;
    }

    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL || registration->callbacks.stop == NULL) {
        return TRUE;
    }

    return registration->callbacks.stop(instance_context);
}

static gboolean swift_gst_base_transform_set_caps(
    GstBaseTransform* transform,
    GstCaps* input_caps,
    GstCaps* output_caps
) {
    void* instance_context = swift_gst_base_transform_instance_context(transform);
    if (instance_context == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL || registration->callbacks.set_caps == NULL) {
        return FALSE;
    }

    return registration->callbacks.set_caps(instance_context, input_caps, output_caps);
}

static GstFlowReturn swift_gst_base_transform_transform_ip(
    GstBaseTransform* transform,
    GstBuffer* buffer
) {
    if (buffer == NULL || !gst_buffer_is_writable(buffer)) {
        return GST_FLOW_ERROR;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    if (instance_context == NULL) {
        return GST_FLOW_ERROR;
    }

    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL || registration->callbacks.transform_ip == NULL) {
        return GST_FLOW_ERROR;
    }

    return registration->callbacks.transform_ip(instance_context, buffer);
}

static GstFlowReturn swift_gst_base_transform_prepare_output_buffer(
    GstBaseTransform* transform,
    GstBuffer* input,
    GstBuffer** output
) {
    (void)transform;

    if (input == NULL || output == NULL) {
        return GST_FLOW_ERROR;
    }

    gsize size = gst_buffer_get_size(input);
    GstBuffer* allocated = swift_gst_base_transform_allocate_output(input, size);
    if (allocated == NULL) {
        *output = NULL;
        return GST_FLOW_ERROR;
    }

    GST_BUFFER_PTS(allocated) = GST_BUFFER_PTS(input);
    GST_BUFFER_DURATION(allocated) = GST_BUFFER_DURATION(input);
    *output = allocated;
    return GST_FLOW_OK;
}

static GstFlowReturn swift_gst_base_transform_transform(
    GstBaseTransform* transform,
    GstBuffer* input,
    GstBuffer* output
) {
    if (input == NULL || output == NULL || !gst_buffer_is_writable(output)) {
        return GST_FLOW_ERROR;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    if (instance_context == NULL) {
        return GST_FLOW_ERROR;
    }

    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (registration == NULL || registration->callbacks.transform == NULL) {
        return GST_FLOW_ERROR;
    }

    return registration->callbacks.transform(instance_context, input, output);
}

static GstBaseTransformClass* swift_gst_base_transform_parent_class(GstBaseTransform* transform) {
    if (transform == NULL) {
        return NULL;
    }

    return GST_BASE_TRANSFORM_CLASS(g_type_class_peek_parent(G_OBJECT_GET_CLASS(transform)));
}

static GstCaps* swift_gst_base_transform_transform_caps(
    GstBaseTransform* transform,
    GstPadDirection direction,
    GstCaps* caps,
    GstCaps* filter
) {
    if (transform == NULL || caps == NULL) {
        return NULL;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.transform_caps == NULL) {
        return NULL;
    }

    SwiftGstBaseTransformCapsResult result =
        registration->callbacks.transform_caps(instance_context, direction, caps, filter);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        return result.caps;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->transform_caps != NULL
            ? parent_class->transform_caps(transform, direction, caps, filter)
            : NULL;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        if (result.caps != NULL) {
            gst_caps_unref(result.caps);
        }
        return NULL;
    }
}

static GstCaps* swift_gst_base_transform_fixate_caps(
    GstBaseTransform* transform,
    GstPadDirection direction,
    GstCaps* caps,
    GstCaps* othercaps
) {
    if (transform == NULL || caps == NULL || othercaps == NULL) {
        if (othercaps != NULL) {
            gst_caps_unref(othercaps);
        }
        return NULL;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.fixate_caps == NULL) {
        gst_caps_unref(othercaps);
        return NULL;
    }

    SwiftGstBaseTransformCapsResult result =
        registration->callbacks.fixate_caps(instance_context, direction, caps, othercaps);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        gst_caps_unref(othercaps);
        return result.caps;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        if (parent_class != NULL && parent_class->fixate_caps != NULL) {
            return parent_class->fixate_caps(transform, direction, caps, othercaps);
        }
        gst_caps_unref(othercaps);
        return NULL;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        gst_caps_unref(othercaps);
        if (result.caps != NULL) {
            gst_caps_unref(result.caps);
        }
        return NULL;
    }
}

static gboolean swift_gst_base_transform_get_unit_size(
    GstBaseTransform* transform,
    GstCaps* caps,
    gsize* size
) {
    if (transform == NULL || caps == NULL || size == NULL) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.get_unit_size == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformSizeResult result =
        registration->callbacks.get_unit_size(instance_context, caps);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        if (result.size == 0) {
            return FALSE;
        }
        *size = result.size;
        return TRUE;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->get_unit_size != NULL
            ? parent_class->get_unit_size(transform, caps, size)
            : FALSE;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static gboolean swift_gst_base_transform_transform_size(
    GstBaseTransform* transform,
    GstPadDirection direction,
    GstCaps* caps,
    gsize size,
    GstCaps* othercaps,
    gsize* othersize
) {
    if (transform == NULL || caps == NULL || othercaps == NULL || othersize == NULL) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.transform_size == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformSizeResult result =
        registration->callbacks.transform_size(instance_context, direction, caps, size, othercaps);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        if (result.size == 0) {
            return FALSE;
        }
        *othersize = result.size;
        return TRUE;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->transform_size != NULL
            ? parent_class->transform_size(transform, direction, caps, size, othercaps, othersize)
            : FALSE;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static gboolean swift_gst_base_transform_decide_allocation(
    GstBaseTransform* transform,
    GstQuery* query
) {
    if (transform == NULL || query == NULL) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.decide_allocation == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformBoolResult result =
        registration->callbacks.decide_allocation(instance_context, query);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        return result.value;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->decide_allocation != NULL
            ? parent_class->decide_allocation(transform, query)
            : TRUE;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static gboolean swift_gst_base_transform_propose_allocation(
    GstBaseTransform* transform,
    GstQuery* decide_query,
    GstQuery* query
) {
    if (transform == NULL || query == NULL) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.propose_allocation == NULL
        || decide_query == NULL) {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->propose_allocation != NULL
            ? parent_class->propose_allocation(transform, decide_query, query)
            : TRUE;
    }

    SwiftGstBaseTransformBoolResult result =
        registration->callbacks.propose_allocation(instance_context, decide_query, query);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        return result.value;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->propose_allocation != NULL
            ? parent_class->propose_allocation(transform, decide_query, query)
            : TRUE;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static gboolean swift_gst_base_transform_filter_meta(
    GstBaseTransform* transform,
    GstQuery* query,
    GType api,
    const GstStructure* params
) {
    if (transform == NULL || query == NULL || api == 0) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.filter_meta == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformBoolResult result =
        registration->callbacks.filter_meta(instance_context, query, api, params);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        return result.value;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->filter_meta != NULL
            ? parent_class->filter_meta(transform, query, api, params)
            : FALSE;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static gboolean swift_gst_base_transform_copy_metadata(
    GstBaseTransform* transform,
    GstBuffer* input,
    GstBuffer* output
) {
    if (transform == NULL || input == NULL || output == NULL) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.copy_metadata == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformBoolResult result =
        registration->callbacks.copy_metadata(instance_context, input, output);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        return result.value;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        if (parent_class != NULL && parent_class->copy_metadata != NULL) {
            return parent_class->copy_metadata(transform, input, output);
        }
        return gst_buffer_copy_into(output, input, GST_BUFFER_COPY_METADATA, 0, -1);
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static gboolean swift_gst_base_transform_transform_meta(
    GstBaseTransform* transform,
    GstBuffer* output,
    GstMeta* metadata,
    GstBuffer* input
) {
    if (transform == NULL || output == NULL || metadata == NULL || input == NULL) {
        return FALSE;
    }

    void* instance_context = swift_gst_base_transform_instance_context(transform);
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(transform);
    if (instance_context == NULL
        || registration == NULL
        || registration->callbacks.transform_meta == NULL) {
        return FALSE;
    }

    SwiftGstBaseTransformBoolResult result =
        registration->callbacks.transform_meta(instance_context, output, metadata, input);
    switch (result.status) {
    case SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE:
        return result.value;
    case SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT: {
        GstBaseTransformClass* parent_class = swift_gst_base_transform_parent_class(transform);
        return parent_class != NULL && parent_class->transform_meta != NULL
            ? parent_class->transform_meta(transform, output, metadata, input)
            : TRUE;
    }
    case SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE:
    default:
        return FALSE;
    }
}

static void swift_gst_base_transform_finalize(GObject* object) {
    SwiftGstNativeBaseTransform* transform = (SwiftGstNativeBaseTransform*)object;
    SwiftGstBaseTransformRegistration* registration =
        swift_gst_base_transform_class_registration(GST_BASE_TRANSFORM(object));

    if (transform->instance_context != NULL) {
        void* instance_context = transform->instance_context;
        transform->instance_context = NULL;

        if (registration != NULL && registration->callbacks.destroy_instance != NULL) {
            registration->callbacks.destroy_instance(instance_context);
        }
    }

    GObjectClass* parent_class = G_OBJECT_CLASS(
        g_type_class_peek_parent(G_OBJECT_GET_CLASS(object))
    );
    if (parent_class != NULL && parent_class->finalize != NULL) {
        parent_class->finalize(object);
    }
}

static void swift_gst_base_transform_add_pad_template(
    GstElementClass* element_class,
    const gchar* name,
    GstPadDirection direction,
    const gchar* caps_string
) {
    GstCaps* caps = gst_caps_from_string(caps_string);
    if (caps == NULL) {
        return;
    }

    GstPadTemplate* pad_template = gst_pad_template_new(
        name,
        direction,
        GST_PAD_ALWAYS,
        caps
    );
    gst_caps_unref(caps);

    if (pad_template != NULL) {
        gst_element_class_add_pad_template(element_class, pad_template);
    }
}

static void swift_gst_base_transform_class_init(gpointer g_class, gpointer class_data) {
    SwiftGstNativeBaseTransformClass* native_class =
        (SwiftGstNativeBaseTransformClass*)g_class;
    SwiftGstBaseTransformRegistration* registration =
        (SwiftGstBaseTransformRegistration*)class_data;
    native_class->registration = registration;

    GObjectClass* object_class = G_OBJECT_CLASS(g_class);
    object_class->finalize = swift_gst_base_transform_finalize;
    if (registration != NULL && registration->property_count > 0) {
        object_class->set_property = swift_gst_base_transform_set_property;
        object_class->get_property = swift_gst_base_transform_get_property;
        swift_gst_native_properties_install(
            object_class,
            registration->properties,
            registration->property_count,
            "BaseTransform"
        );
    }

    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_CLASS(g_class);
    transform_class->start = swift_gst_base_transform_start;
    transform_class->stop = swift_gst_base_transform_stop;
    transform_class->set_caps = swift_gst_base_transform_set_caps;

    if (registration == NULL) {
        return;
    }

    if (registration->mode == SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE) {
        transform_class->transform = swift_gst_base_transform_transform;
        transform_class->prepare_output_buffer = swift_gst_base_transform_prepare_output_buffer;
        transform_class->passthrough_on_same_caps = FALSE;
        transform_class->transform_ip_on_passthrough = FALSE;
    } else if (registration->mode == SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE_GENERAL) {
        transform_class->transform = swift_gst_base_transform_transform;
        transform_class->transform_caps = swift_gst_base_transform_transform_caps;
        transform_class->fixate_caps = swift_gst_base_transform_fixate_caps;
        transform_class->get_unit_size = swift_gst_base_transform_get_unit_size;
        transform_class->transform_size = swift_gst_base_transform_transform_size;
        transform_class->decide_allocation = swift_gst_base_transform_decide_allocation;
        transform_class->propose_allocation = swift_gst_base_transform_propose_allocation;
        transform_class->filter_meta = swift_gst_base_transform_filter_meta;
        transform_class->copy_metadata = swift_gst_base_transform_copy_metadata;
        transform_class->transform_meta = swift_gst_base_transform_transform_meta;
        transform_class->passthrough_on_same_caps = FALSE;
        transform_class->transform_ip_on_passthrough = FALSE;
    } else {
        transform_class->transform_ip = swift_gst_base_transform_transform_ip;
        transform_class->passthrough_on_same_caps = registration->passthrough_on_same_caps;
        transform_class->transform_ip_on_passthrough = registration->transform_ip_on_passthrough;
    }

    GstElementClass* element_class = GST_ELEMENT_CLASS(g_class);
    gst_element_class_set_static_metadata(
        element_class,
        registration->long_name,
        registration->klass,
        registration->description,
        registration->author
    );

    swift_gst_base_transform_add_pad_template(
        element_class,
        "sink",
        GST_PAD_SINK,
        registration->sink_caps
    );
    swift_gst_base_transform_add_pad_template(
        element_class,
        "src",
        GST_PAD_SRC,
        registration->src_caps
    );
}

static void swift_gst_base_transform_instance_init(GTypeInstance* instance, gpointer g_class) {
    SwiftGstNativeBaseTransform* transform = (SwiftGstNativeBaseTransform*)instance;
    SwiftGstNativeBaseTransformClass* klass = (SwiftGstNativeBaseTransformClass*)g_class;
    SwiftGstBaseTransformRegistration* registration =
        klass != NULL ? klass->registration : NULL;

    gboolean in_place = registration == NULL
        || registration->mode == SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE;
    gst_base_transform_set_in_place(GST_BASE_TRANSFORM(instance), in_place);
    transform->instance_context = NULL;
    if (registration == NULL
        || registration->class_context == NULL
        || registration->callbacks.create_instance == NULL) {
        return;
    }

    transform->instance_context =
        registration->callbacks.create_instance(registration->class_context);
}

static gboolean swift_gst_base_transform_validate_caps(
    const gchar* caps_string,
    const gchar* diagnostic_name,
    gchar** error_message
) {
    if (!swift_gst_base_sink_is_non_empty(caps_string)) {
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform %s caps are empty",
            diagnostic_name
        );
    }

    GstCaps* caps = gst_caps_from_string(caps_string);
    if (caps == NULL) {
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform %s caps could not be parsed",
            diagnostic_name
        );
    }

    gboolean valid_caps = !gst_caps_is_empty(caps);
    gst_caps_unref(caps);
    if (!valid_caps) {
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform %s caps are empty",
            diagnostic_name
        );
    }

    return TRUE;
}

static gboolean swift_gst_base_transform_validate_info(
    const SwiftGstBaseTransformInfo* info,
    const SwiftGstBaseTransformCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    if (info == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform registration info is NULL");
    }
    if (callbacks == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform registration callbacks are NULL");
    }
    if (class_context == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform class context is NULL");
    }
    if (retain_class_context == NULL) {
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform class context retain callback is NULL"
        );
    }
    if (release_class_context == NULL) {
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform class context release callback is NULL"
        );
    }
    if (!swift_gst_base_sink_is_valid_factory_name(info->factory_name)) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform factory name is invalid");
    }
    if (!swift_gst_base_sink_is_valid_type_name(info->type_name)) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform GType name is invalid");
    }
    if (!swift_gst_base_sink_is_non_empty(info->klass)) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform metadata klass is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->long_name)) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform metadata long name is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->description)) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform metadata description is empty");
    }
    if (!swift_gst_base_sink_is_non_empty(info->author)) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform metadata author is empty");
    }
    if (callbacks->destroy_instance == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform destroy_instance callback is NULL");
    }
    if (callbacks->start == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform start callback is NULL");
    }
    if (callbacks->stop == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform stop callback is NULL");
    }
    if (callbacks->set_caps == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform set_caps callback is NULL");
    }

    switch (info->mode) {
    case SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE:
        if (callbacks->transform_ip == NULL) {
            return swift_gst_base_transform_fail(error_message, "BaseTransform transform_ip callback is NULL");
        }
        break;
    case SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE:
        if (callbacks->transform == NULL) {
            return swift_gst_base_transform_fail(error_message, "BaseTransform transform callback is NULL");
        }
        break;
    case SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE_GENERAL:
        if (callbacks->transform == NULL) {
            return swift_gst_base_transform_fail(error_message, "BaseTransform transform callback is NULL");
        }
        if (callbacks->transform_caps == NULL
            || callbacks->fixate_caps == NULL
            || callbacks->get_unit_size == NULL
            || callbacks->transform_size == NULL
            || callbacks->decide_allocation == NULL
            || callbacks->propose_allocation == NULL
            || callbacks->filter_meta == NULL
            || callbacks->copy_metadata == NULL
            || callbacks->transform_meta == NULL) {
            return swift_gst_base_transform_fail(
                error_message,
                "BaseTransform general-mode callbacks are incomplete"
            );
        }
        break;
    default:
        return swift_gst_base_transform_fail(error_message, "BaseTransform mode is invalid");
    }
    if (!swift_gst_base_transform_validate_caps(info->sink_caps, "sink", error_message)) {
        return FALSE;
    }
    if (!swift_gst_base_transform_validate_caps(info->src_caps, "src", error_message)) {
        return FALSE;
    }

    return TRUE;
}

static gboolean swift_gst_register_base_transform_with_plugin(
    GstPlugin* plugin,
    const SwiftGstBaseTransformInfo* info,
    const SwiftGstBaseTransformCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    if (error_message == NULL) {
        return FALSE;
    }
    *error_message = NULL;

    if (!swift_gst_base_transform_validate_info(
        info,
        callbacks,
        class_context,
        retain_class_context,
        release_class_context,
        error_message
    )) {
        return FALSE;
    }

    SwiftGstBaseTransformRegistration* registration =
        g_new0(SwiftGstBaseTransformRegistration, 1);
    registration->factory_name = g_strdup(info->factory_name);
    registration->type_name = g_strdup(info->type_name);
    registration->klass = g_strdup(info->klass);
    registration->long_name = g_strdup(info->long_name);
    registration->description = g_strdup(info->description);
    registration->author = g_strdup(info->author);
    registration->sink_caps = g_strdup(info->sink_caps);
    registration->src_caps = g_strdup(info->src_caps);
    registration->rank = info->rank;
    registration->mode = info->mode;
    registration->passthrough_on_same_caps = info->passthrough_on_same_caps;
    registration->transform_ip_on_passthrough = info->transform_ip_on_passthrough;
    registration->property_count = info->property_count;
    if (!swift_gst_native_property_descriptors_copy(
        info->properties,
        info->property_count,
        "BaseTransform",
        &registration->properties,
        error_message
    )) {
        swift_gst_base_transform_free_registration(registration);
        return FALSE;
    }
    registration->callbacks = *callbacks;
    registration->release_class_context = release_class_context;

    retain_class_context(class_context);
    registration->class_context = class_context;

    gboolean success = FALSE;
    gboolean type_registered = FALSE;

    g_mutex_lock(&swift_gst_base_transform_registration_mutex);

    if (g_type_from_name(registration->type_name) != 0) {
        g_mutex_unlock(&swift_gst_base_transform_registration_mutex);
        swift_gst_base_transform_free_registration(registration);
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform GType '%s' is already registered",
            info->type_name
        );
    }

    GstElementFactory* existing_factory = gst_element_factory_find(registration->factory_name);
    if (existing_factory != NULL) {
        gst_object_unref(existing_factory);
        g_mutex_unlock(&swift_gst_base_transform_registration_mutex);
        swift_gst_base_transform_free_registration(registration);
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform factory '%s' is already registered",
            info->factory_name
        );
    }

    GTypeInfo type_info = {
        .class_size = sizeof(SwiftGstNativeBaseTransformClass),
        .base_init = NULL,
        .base_finalize = NULL,
        .class_init = swift_gst_base_transform_class_init,
        .class_finalize = NULL,
        .class_data = registration,
        .instance_size = sizeof(SwiftGstNativeBaseTransform),
        .n_preallocs = 0,
        .instance_init = swift_gst_base_transform_instance_init,
        .value_table = NULL,
    };

    GType type = g_type_register_static(
        GST_TYPE_BASE_TRANSFORM,
        registration->type_name,
        &type_info,
        0
    );
    if (type == 0) {
        g_mutex_unlock(&swift_gst_base_transform_registration_mutex);
        swift_gst_base_transform_free_registration(registration);
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform GType '%s' could not be registered",
            info->type_name
        );
    }
    type_registered = TRUE;

    success = gst_element_register(plugin, registration->factory_name, registration->rank, type);

    g_mutex_unlock(&swift_gst_base_transform_registration_mutex);

    if (!success) {
        if (type_registered) {
            swift_gst_base_transform_deactivate_registration(registration);
        } else {
            swift_gst_base_transform_free_registration(registration);
        }
        return swift_gst_base_transform_fail(
            error_message,
            "BaseTransform factory '%s' could not be registered",
            info->factory_name
        );
    }

    *error_message = NULL;
    return TRUE;
}

gboolean swift_gst_register_base_transform(
    const SwiftGstBaseTransformInfo* info,
    const SwiftGstBaseTransformCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    return swift_gst_register_base_transform_with_plugin(
        NULL,
        info,
        callbacks,
        class_context,
        retain_class_context,
        release_class_context,
        error_message
    );
}

gboolean swift_gst_register_base_transform_for_plugin(
    GstPlugin* plugin,
    const SwiftGstBaseTransformInfo* info,
    const SwiftGstBaseTransformCallbacks* callbacks,
    void* class_context,
    SwiftGstContextRetainFunc retain_class_context,
    SwiftGstContextReleaseFunc release_class_context,
    gchar** error_message
) {
    if (error_message == NULL) {
        return FALSE;
    }
    *error_message = NULL;
    if (plugin == NULL) {
        return swift_gst_base_transform_fail(
            error_message,
            "Static plugin BaseTransform plugin is NULL"
        );
    }
    return swift_gst_register_base_transform_with_plugin(
        plugin,
        info,
        callbacks,
        class_context,
        retain_class_context,
        release_class_context,
        error_message
    );
}
