#include "GStreamerBaseShimInternal.h"

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

static GMutex swift_gst_base_sink_registration_mutex;

GstFlowReturn swift_gst_base_sink_flow_dropped(void) {
#ifdef GST_BASE_SINK_FLOW_DROPPED
    return GST_BASE_SINK_FLOW_DROPPED;
#else
    return GST_FLOW_CUSTOM_SUCCESS;
#endif
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

    if (plugin == NULL) {
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
