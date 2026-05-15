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
    gboolean passthrough_on_same_caps;
    gboolean transform_ip_on_passthrough;
    SwiftGstBaseTransformCallbacks callbacks;
    void* class_context;
    SwiftGstContextReleaseFunc release_class_context;
} SwiftGstBaseTransformRegistration;

static GMutex swift_gst_base_sink_registration_mutex;
static GMutex swift_gst_base_transform_registration_mutex;

static gboolean swift_gst_base_sink_fail(gchar** error_message, const gchar* format, ...) {
    if (error_message != NULL) {
        va_list args;
        va_start(args, format);
        *error_message = g_strdup_vprintf(format, args);
        va_end(args);
    }

    return FALSE;
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

gboolean swift_gst_register_base_sink(
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

    success = gst_element_register(
        NULL,
        registration->factory_name,
        registration->rank,
        type
    );

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

    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_CLASS(g_class);
    transform_class->start = swift_gst_base_transform_start;
    transform_class->stop = swift_gst_base_transform_stop;
    transform_class->set_caps = swift_gst_base_transform_set_caps;
    transform_class->transform_ip = swift_gst_base_transform_transform_ip;

    if (registration == NULL) {
        return;
    }

    transform_class->passthrough_on_same_caps = registration->passthrough_on_same_caps;
    transform_class->transform_ip_on_passthrough = registration->transform_ip_on_passthrough;

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

    gst_base_transform_set_in_place(GST_BASE_TRANSFORM(instance), TRUE);
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
    if (callbacks->transform_ip == NULL) {
        return swift_gst_base_transform_fail(error_message, "BaseTransform transform_ip callback is NULL");
    }
    if (!swift_gst_base_transform_validate_caps(info->sink_caps, "sink", error_message)) {
        return FALSE;
    }
    if (!swift_gst_base_transform_validate_caps(info->src_caps, "src", error_message)) {
        return FALSE;
    }

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
    registration->passthrough_on_same_caps = info->passthrough_on_same_caps;
    registration->transform_ip_on_passthrough = info->transform_ip_on_passthrough;
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

    success = gst_element_register(
        NULL,
        registration->factory_name,
        registration->rank,
        type
    );

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
