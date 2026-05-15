#include "include/CGStreamerTestSupport.h"
#include "GStreamerAppShim.h"
#include "GStreamerBaseShim.h"

#define SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_TIMEOUT_US (5 * G_TIME_SPAN_SECOND)
#define SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EXPECTED_RETAIN_COUNT 2
#define SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EXPECTED_RELEASE_COUNT 2

typedef enum {
    SWIFT_GST_TEST_PROBE_ERROR,
    SWIFT_GST_TEST_PROBE_MARKER,
} SwiftGstTestProbeMode;

struct SwiftGstTestProbe {
    GMutex mutex;
    GstElement* pipeline;
    GstPad* pad;
    gulong probe_id;
    guint after_buffers;
    guint buffer_count;
    gboolean acknowledged;
    SwiftGstTestProbeMode mode;
    gchar* message;
    gchar* debug;
    gchar* marker;
};

typedef struct {
    GstAppSink* appsink;
    GMutex mutex;
    GCond cond;
    gboolean callback_entered;
    gboolean release_callback;
    gboolean emit_completed;
    guint callback_count;
    guint retain_count;
    guint release_count;
    GstFlowReturn flow_return;
} SwiftGstTestCallbackRegistrationRaceContext;

typedef struct {
    GMutex mutex;
    guint retain_count;
    guint release_count;
    guint create_count;
    guint destroy_count;
    guint start_count;
    guint stop_count;
    guint set_caps_count;
    guint render_count;
} SwiftGstTestBaseSinkContext;

typedef struct {
    GMutex mutex;
    guint retain_count;
    guint release_count;
    guint create_count;
    guint destroy_count;
    guint start_count;
    guint stop_count;
    guint set_caps_count;
    guint transform_ip_count;
} SwiftGstTestBaseTransformContext;

static GMutex swift_gst_test_base_sink_missing_probe_mutex;
static SwiftGstTestBaseSinkContext* swift_gst_test_base_sink_missing_probe_context = NULL;
static GMutex swift_gst_test_base_transform_missing_probe_mutex;
static SwiftGstTestBaseTransformContext* swift_gst_test_base_transform_missing_probe_context = NULL;

static void swift_gst_test_base_sink_context_init(SwiftGstTestBaseSinkContext* context) {
    if (!context) {
        return;
    }

    g_mutex_init(&context->mutex);
}

static void swift_gst_test_base_sink_increment(
    SwiftGstTestBaseSinkContext* context,
    guint* field
) {
    if (!context || !field) {
        return;
    }

    g_mutex_lock(&context->mutex);
    *field += 1;
    g_mutex_unlock(&context->mutex);
}

static SwiftGstTestBaseSinkCallbackCounts swift_gst_test_base_sink_counts(
    SwiftGstTestBaseSinkContext* context
) {
    SwiftGstTestBaseSinkCallbackCounts counts = {0};

    if (!context) {
        return counts;
    }

    g_mutex_lock(&context->mutex);
    counts.retain_count = context->retain_count;
    counts.release_count = context->release_count;
    counts.create_count = context->create_count;
    counts.destroy_count = context->destroy_count;
    counts.start_count = context->start_count;
    counts.stop_count = context->stop_count;
    counts.set_caps_count = context->set_caps_count;
    counts.render_count = context->render_count;
    g_mutex_unlock(&context->mutex);

    return counts;
}

static SwiftGstTestBaseSinkContext* swift_gst_test_base_sink_current_missing_probe_context(void) {
    g_mutex_lock(&swift_gst_test_base_sink_missing_probe_mutex);
    SwiftGstTestBaseSinkContext* context = swift_gst_test_base_sink_missing_probe_context;
    g_mutex_unlock(&swift_gst_test_base_sink_missing_probe_mutex);
    return context;
}

static void swift_gst_test_base_sink_set_missing_probe_context(
    SwiftGstTestBaseSinkContext* context
) {
    g_mutex_lock(&swift_gst_test_base_sink_missing_probe_mutex);
    swift_gst_test_base_sink_missing_probe_context = context;
    g_mutex_unlock(&swift_gst_test_base_sink_missing_probe_mutex);
}

static SwiftGstTestBaseSinkContext* swift_gst_test_base_sink_callback_context(
    void* instance_context
) {
    if (instance_context) {
        return (SwiftGstTestBaseSinkContext*)instance_context;
    }

    return swift_gst_test_base_sink_current_missing_probe_context();
}

static void swift_gst_test_base_sink_retain(void* data) {
    SwiftGstTestBaseSinkContext* context = (SwiftGstTestBaseSinkContext*)data;
    if (!context) {
        return;
    }
    swift_gst_test_base_sink_increment(context, &context->retain_count);
}

static void swift_gst_test_base_sink_release(void* data) {
    SwiftGstTestBaseSinkContext* context = (SwiftGstTestBaseSinkContext*)data;
    if (!context) {
        return;
    }
    swift_gst_test_base_sink_increment(context, &context->release_count);
}

static void* swift_gst_test_base_sink_create_instance(void* class_context) {
    SwiftGstTestBaseSinkContext* context = (SwiftGstTestBaseSinkContext*)class_context;
    if (!context) {
        return NULL;
    }
    swift_gst_test_base_sink_increment(context, &context->create_count);
    return context;
}

static void swift_gst_test_base_sink_destroy_instance(void* instance_context) {
    SwiftGstTestBaseSinkContext* context = swift_gst_test_base_sink_callback_context(instance_context);
    if (!context) {
        return;
    }
    swift_gst_test_base_sink_increment(context, &context->destroy_count);
}

static gboolean swift_gst_test_base_sink_start(void* instance_context) {
    SwiftGstTestBaseSinkContext* context = swift_gst_test_base_sink_callback_context(instance_context);
    if (!context) {
        return FALSE;
    }
    swift_gst_test_base_sink_increment(context, &context->start_count);
    return TRUE;
}

static gboolean swift_gst_test_base_sink_stop(void* instance_context) {
    SwiftGstTestBaseSinkContext* context = swift_gst_test_base_sink_callback_context(instance_context);
    if (!context) {
        return TRUE;
    }
    swift_gst_test_base_sink_increment(context, &context->stop_count);
    return TRUE;
}

static gboolean swift_gst_test_base_sink_set_caps(void* instance_context, GstCaps* caps) {
    (void)caps;

    SwiftGstTestBaseSinkContext* context = swift_gst_test_base_sink_callback_context(instance_context);
    if (!context) {
        return FALSE;
    }
    swift_gst_test_base_sink_increment(context, &context->set_caps_count);
    return TRUE;
}

static GstFlowReturn swift_gst_test_base_sink_render(void* instance_context, GstBuffer* buffer) {
    (void)buffer;

    SwiftGstTestBaseSinkContext* context = swift_gst_test_base_sink_callback_context(instance_context);
    if (!context) {
        return GST_FLOW_ERROR;
    }
    swift_gst_test_base_sink_increment(context, &context->render_count);
    return GST_FLOW_OK;
}

static SwiftGstBaseSinkInfo swift_gst_test_base_sink_info(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstBaseSinkInfo info = {
        .factory_name = factory_name,
        .type_name = type_name,
        .klass = "Sink/Video",
        .long_name = "Swift test BaseSink",
        .description = "Swift test BaseSink registered through the C ABI",
        .author = "gstreamer-swift-tests",
        .rank = 0,
        .sink_caps = "video/x-raw",
    };
    return info;
}

static SwiftGstBaseSinkCallbacks swift_gst_test_base_sink_callbacks(void) {
    SwiftGstBaseSinkCallbacks callbacks = {
        .create_instance = swift_gst_test_base_sink_create_instance,
        .destroy_instance = swift_gst_test_base_sink_destroy_instance,
        .start = swift_gst_test_base_sink_start,
        .stop = swift_gst_test_base_sink_stop,
        .set_caps = swift_gst_test_base_sink_set_caps,
        .render = swift_gst_test_base_sink_render,
    };
    return callbacks;
}

static gboolean swift_gst_test_base_sink_register(
    const gchar* factory_name,
    const gchar* type_name,
    SwiftGstTestBaseSinkContext* context,
    const SwiftGstBaseSinkCallbacks* callbacks
) {
    SwiftGstBaseSinkInfo info = swift_gst_test_base_sink_info(factory_name, type_name);
    gchar* error_message = NULL;
    gboolean registered = swift_gst_register_base_sink(
        &info,
        callbacks,
        context,
        swift_gst_test_base_sink_retain,
        swift_gst_test_base_sink_release,
        &error_message
    );

    g_free(error_message);
    return registered;
}

static void swift_gst_test_base_transform_context_init(SwiftGstTestBaseTransformContext* context) {
    if (!context) {
        return;
    }

    g_mutex_init(&context->mutex);
}

static void swift_gst_test_base_transform_increment(
    SwiftGstTestBaseTransformContext* context,
    guint* field
) {
    if (!context || !field) {
        return;
    }

    g_mutex_lock(&context->mutex);
    *field += 1;
    g_mutex_unlock(&context->mutex);
}

static SwiftGstTestBaseTransformCallbackCounts swift_gst_test_base_transform_counts(
    SwiftGstTestBaseTransformContext* context
) {
    SwiftGstTestBaseTransformCallbackCounts counts = {0};

    if (!context) {
        return counts;
    }

    g_mutex_lock(&context->mutex);
    counts.retain_count = context->retain_count;
    counts.release_count = context->release_count;
    counts.create_count = context->create_count;
    counts.destroy_count = context->destroy_count;
    counts.start_count = context->start_count;
    counts.stop_count = context->stop_count;
    counts.set_caps_count = context->set_caps_count;
    counts.transform_ip_count = context->transform_ip_count;
    g_mutex_unlock(&context->mutex);

    return counts;
}

static SwiftGstTestBaseTransformContext* swift_gst_test_base_transform_current_missing_probe_context(void) {
    g_mutex_lock(&swift_gst_test_base_transform_missing_probe_mutex);
    SwiftGstTestBaseTransformContext* context = swift_gst_test_base_transform_missing_probe_context;
    g_mutex_unlock(&swift_gst_test_base_transform_missing_probe_mutex);
    return context;
}

static void swift_gst_test_base_transform_set_missing_probe_context(
    SwiftGstTestBaseTransformContext* context
) {
    g_mutex_lock(&swift_gst_test_base_transform_missing_probe_mutex);
    swift_gst_test_base_transform_missing_probe_context = context;
    g_mutex_unlock(&swift_gst_test_base_transform_missing_probe_mutex);
}

static SwiftGstTestBaseTransformContext* swift_gst_test_base_transform_callback_context(
    void* instance_context
) {
    if (instance_context) {
        return (SwiftGstTestBaseTransformContext*)instance_context;
    }

    return swift_gst_test_base_transform_current_missing_probe_context();
}

static void swift_gst_test_base_transform_retain(void* data) {
    SwiftGstTestBaseTransformContext* context = (SwiftGstTestBaseTransformContext*)data;
    if (!context) {
        return;
    }
    swift_gst_test_base_transform_increment(context, &context->retain_count);
}

static void swift_gst_test_base_transform_release(void* data) {
    SwiftGstTestBaseTransformContext* context = (SwiftGstTestBaseTransformContext*)data;
    if (!context) {
        return;
    }
    swift_gst_test_base_transform_increment(context, &context->release_count);
}

static void* swift_gst_test_base_transform_create_instance(void* class_context) {
    SwiftGstTestBaseTransformContext* context = (SwiftGstTestBaseTransformContext*)class_context;
    if (!context) {
        return NULL;
    }
    swift_gst_test_base_transform_increment(context, &context->create_count);
    return context;
}

static void swift_gst_test_base_transform_destroy_instance(void* instance_context) {
    SwiftGstTestBaseTransformContext* context =
        swift_gst_test_base_transform_callback_context(instance_context);
    if (!context) {
        return;
    }
    swift_gst_test_base_transform_increment(context, &context->destroy_count);
}

static gboolean swift_gst_test_base_transform_start(void* instance_context) {
    SwiftGstTestBaseTransformContext* context =
        swift_gst_test_base_transform_callback_context(instance_context);
    if (!context) {
        return FALSE;
    }
    swift_gst_test_base_transform_increment(context, &context->start_count);
    return TRUE;
}

static gboolean swift_gst_test_base_transform_stop(void* instance_context) {
    SwiftGstTestBaseTransformContext* context =
        swift_gst_test_base_transform_callback_context(instance_context);
    if (!context) {
        return TRUE;
    }
    swift_gst_test_base_transform_increment(context, &context->stop_count);
    return TRUE;
}

static gboolean swift_gst_test_base_transform_set_caps(
    void* instance_context,
    GstCaps* input_caps,
    GstCaps* output_caps
) {
    (void)input_caps;
    (void)output_caps;

    SwiftGstTestBaseTransformContext* context =
        swift_gst_test_base_transform_callback_context(instance_context);
    if (!context) {
        return FALSE;
    }
    swift_gst_test_base_transform_increment(context, &context->set_caps_count);
    return TRUE;
}

static GstFlowReturn swift_gst_test_base_transform_ip(
    void* instance_context,
    GstBuffer* buffer
) {
    (void)buffer;

    SwiftGstTestBaseTransformContext* context =
        swift_gst_test_base_transform_callback_context(instance_context);
    if (!context) {
        return GST_FLOW_ERROR;
    }
    swift_gst_test_base_transform_increment(context, &context->transform_ip_count);
    return GST_FLOW_OK;
}

static SwiftGstBaseTransformInfo swift_gst_test_base_transform_info(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstBaseTransformInfo info = {
        .factory_name = factory_name,
        .type_name = type_name,
        .klass = "Filter/Effect/Video",
        .long_name = "Swift test BaseTransform",
        .description = "Swift test BaseTransform registered through the C ABI",
        .author = "gstreamer-swift-tests",
        .rank = 0,
        .sink_caps = "video/x-raw",
        .src_caps = "video/x-raw",
        .passthrough_on_same_caps = TRUE,
        .transform_ip_on_passthrough = FALSE,
    };
    return info;
}

static SwiftGstBaseTransformCallbacks swift_gst_test_base_transform_callbacks(void) {
    SwiftGstBaseTransformCallbacks callbacks = {
        .create_instance = swift_gst_test_base_transform_create_instance,
        .destroy_instance = swift_gst_test_base_transform_destroy_instance,
        .start = swift_gst_test_base_transform_start,
        .stop = swift_gst_test_base_transform_stop,
        .set_caps = swift_gst_test_base_transform_set_caps,
        .transform_ip = swift_gst_test_base_transform_ip,
    };
    return callbacks;
}

static gboolean swift_gst_test_base_transform_register(
    const gchar* factory_name,
    const gchar* type_name,
    SwiftGstTestBaseTransformContext* context,
    const SwiftGstBaseTransformCallbacks* callbacks
) {
    SwiftGstBaseTransformInfo info = swift_gst_test_base_transform_info(factory_name, type_name);
    gchar* error_message = NULL;
    gboolean registered = swift_gst_register_base_transform(
        &info,
        callbacks,
        context,
        swift_gst_test_base_transform_retain,
        swift_gst_test_base_transform_release,
        &error_message
    );

    g_free(error_message);
    return registered;
}

static SwiftGstTestCallbackRegistrationRaceResult swift_gst_test_callback_registration_race_result(
    SwiftGstTestCallbackRegistrationRaceStatus status,
    SwiftGstTestCallbackRegistrationRaceContext* context
) {
    SwiftGstTestCallbackRegistrationRaceResult result = {
        .success = FALSE,
        .status = status,
        .callback_count = 0,
        .retain_count = 0,
        .release_count = 0,
    };
    gboolean emit_completed = FALSE;

    if (context) {
        g_mutex_lock(&context->mutex);
        result.callback_count = context->callback_count;
        result.retain_count = context->retain_count;
        result.release_count = context->release_count;
        emit_completed = context->emit_completed;
        g_mutex_unlock(&context->mutex);
    }

    if (result.status == SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_OK) {
        if (!emit_completed || result.callback_count != 1) {
            result.status = SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_TIMEOUT;
        } else if (result.retain_count != SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EXPECTED_RETAIN_COUNT
            || result.release_count != SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EXPECTED_RELEASE_COUNT) {
            result.status = SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_UNBALANCED_RETAIN_RELEASE;
        }
    }

    result.success = result.status == SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_OK
        && result.callback_count == 1
        && result.retain_count == SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EXPECTED_RETAIN_COUNT
        && result.release_count == SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EXPECTED_RELEASE_COUNT;
    return result;
}

static void swift_gst_test_callback_registration_race_retain(void* data) {
    SwiftGstTestCallbackRegistrationRaceContext* context =
        (SwiftGstTestCallbackRegistrationRaceContext*)data;
    if (!context) {
        return;
    }

    g_mutex_lock(&context->mutex);
    context->retain_count += 1;
    g_mutex_unlock(&context->mutex);
}

static void swift_gst_test_callback_registration_race_release(void* data) {
    SwiftGstTestCallbackRegistrationRaceContext* context =
        (SwiftGstTestCallbackRegistrationRaceContext*)data;
    if (!context) {
        return;
    }

    g_mutex_lock(&context->mutex);
    context->release_count += 1;
    g_mutex_unlock(&context->mutex);
}

static void swift_gst_test_callback_registration_race_callback(void* data) {
    SwiftGstTestCallbackRegistrationRaceContext* context =
        (SwiftGstTestCallbackRegistrationRaceContext*)data;
    if (!context) {
        return;
    }

    gint64 deadline = g_get_monotonic_time() + SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_TIMEOUT_US;

    g_mutex_lock(&context->mutex);
    context->callback_count += 1;
    context->callback_entered = TRUE;
    g_cond_broadcast(&context->cond);

    while (!context->release_callback) {
        if (!g_cond_wait_until(&context->cond, &context->mutex, deadline)) {
            break;
        }
    }
    g_mutex_unlock(&context->mutex);
}

static gpointer swift_gst_test_callback_registration_race_emit_thread(gpointer data) {
    SwiftGstTestCallbackRegistrationRaceContext* context =
        (SwiftGstTestCallbackRegistrationRaceContext*)data;
    GstFlowReturn flow_return = GST_FLOW_ERROR;

    g_signal_emit_by_name(context->appsink, "new-sample", &flow_return);

    g_mutex_lock(&context->mutex);
    context->flow_return = flow_return;
    context->emit_completed = TRUE;
    g_cond_broadcast(&context->cond);
    g_mutex_unlock(&context->mutex);

    return NULL;
}

static gboolean swift_gst_test_post_probe_message(SwiftGstTestProbe* probe) {
    if (probe->mode == SWIFT_GST_TEST_PROBE_ERROR) {
        return swift_gst_test_post_bus_error(probe->pipeline, probe->message, probe->debug);
    }

    return swift_gst_test_post_element_marker(probe->pipeline, probe->marker);
}

static GstPadProbeReturn swift_gst_test_buffer_probe(
    GstPad* pad,
    GstPadProbeInfo* info,
    gpointer user_data
) {
    (void)pad;

    if ((GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER) == 0) {
        return GST_PAD_PROBE_OK;
    }

    SwiftGstTestProbe* probe = (SwiftGstTestProbe*)user_data;
    gboolean should_post = FALSE;

    g_mutex_lock(&probe->mutex);
    probe->buffer_count += 1;
    if (!probe->acknowledged && probe->buffer_count >= probe->after_buffers) {
        probe->acknowledged = TRUE;
        should_post = TRUE;
    }
    g_mutex_unlock(&probe->mutex);

    if (should_post) {
        swift_gst_test_post_probe_message(probe);
    }

    return GST_PAD_PROBE_OK;
}

static SwiftGstTestProbe* swift_gst_test_install_probe_after_buffers(
    GstElement* pipeline,
    const gchar* element_name,
    const gchar* pad_name,
    guint after_buffers,
    SwiftGstTestProbeMode mode,
    const gchar* message,
    const gchar* debug,
    const gchar* marker
) {
    if (!pipeline || !GST_IS_BIN(pipeline) || !element_name) {
        return NULL;
    }

    GstElement* element = gst_bin_get_by_name(GST_BIN(pipeline), element_name);
    if (!element) {
        return NULL;
    }

    GstPad* pad = gst_element_get_static_pad(element, pad_name ? pad_name : "src");
    gst_object_unref(element);

    if (!pad) {
        return NULL;
    }

    SwiftGstTestProbe* probe = g_new0(SwiftGstTestProbe, 1);
    g_mutex_init(&probe->mutex);
    probe->pipeline = GST_ELEMENT(gst_object_ref(pipeline));
    probe->pad = pad;
    probe->after_buffers = after_buffers == 0 ? 1 : after_buffers;
    probe->mode = mode;
    probe->message = g_strdup(message ? message : "Injected reliable packet test error");
    probe->debug = debug ? g_strdup(debug) : NULL;
    probe->marker = g_strdup(marker ? marker : "swift-gst-test-marker");

    probe->probe_id = gst_pad_add_probe(
        probe->pad,
        GST_PAD_PROBE_TYPE_BUFFER,
        swift_gst_test_buffer_probe,
        probe,
        NULL
    );

    if (probe->probe_id == 0) {
        swift_gst_test_probe_free(probe);
        return NULL;
    }

    return probe;
}

gboolean swift_gst_test_element_factory_exists(const gchar* factory_name) {
    if (!factory_name) {
        return FALSE;
    }

    GstElementFactory* factory = gst_element_factory_find(factory_name);
    if (!factory) {
        return FALSE;
    }

    gst_object_unref(factory);
    return TRUE;
}

guint swift_gst_test_element_factory_rank(const gchar* factory_name) {
    if (!factory_name) {
        return G_MAXUINT;
    }

    GstElementFactory* factory = gst_element_factory_find(factory_name);
    if (!factory) {
        return G_MAXUINT;
    }

    guint rank = gst_plugin_feature_get_rank(GST_PLUGIN_FEATURE(factory));
    gst_object_unref(factory);
    return rank;
}

GLogLevelFlags swift_gst_test_enable_fatal_criticals(void) {
    GLogLevelFlags previous = g_log_set_always_fatal(G_LOG_FATAL_MASK);
    g_log_set_always_fatal(previous | G_LOG_LEVEL_CRITICAL);
    return previous;
}

void swift_gst_test_restore_fatal_mask(GLogLevelFlags previous) {
    g_log_set_always_fatal(previous);
}

SwiftGstTestCallbackRegistrationRaceResult swift_gst_test_callback_registration_disconnect_while_in_flight(void) {
    GstElement* element = gst_element_factory_make("appsink", NULL);
    if (!element) {
        return swift_gst_test_callback_registration_race_result(
            SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_CREATE_APPSINK_FAILED,
            NULL
        );
    }

    SwiftGstTestCallbackRegistrationRaceContext context = {0};
    context.appsink = GST_APP_SINK(element);
    context.flow_return = GST_FLOW_ERROR;
    g_mutex_init(&context.mutex);
    g_cond_init(&context.cond);
    swift_gst_app_sink_set_emit_signals(context.appsink, TRUE);

    SwiftGstCallbackRegistration* registration = swift_gst_app_sink_connect_new_sample(
        context.appsink,
        swift_gst_test_callback_registration_race_callback,
        &context,
        swift_gst_test_callback_registration_race_retain,
        swift_gst_test_callback_registration_race_release
    );

    if (!registration) {
        SwiftGstTestCallbackRegistrationRaceResult result =
            swift_gst_test_callback_registration_race_result(
                SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_CONNECT_FAILED,
                &context
            );
        g_cond_clear(&context.cond);
        g_mutex_clear(&context.mutex);
        gst_object_unref(element);
        return result;
    }

    GError* error = NULL;
    GThread* thread = g_thread_try_new(
        "swift-gst-callback-race",
        swift_gst_test_callback_registration_race_emit_thread,
        &context,
        &error
    );

    if (!thread) {
        if (error) {
            g_error_free(error);
        }

        swift_gst_callback_registration_disconnect(registration);
        SwiftGstTestCallbackRegistrationRaceResult result =
            swift_gst_test_callback_registration_race_result(
                SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EMIT_THREAD_FAILED,
                &context
            );
        g_cond_clear(&context.cond);
        g_mutex_clear(&context.mutex);
        gst_object_unref(element);
        return result;
    }

    SwiftGstTestCallbackRegistrationRaceStatus status =
        SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_OK;
    gint64 deadline = g_get_monotonic_time() + SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_TIMEOUT_US;

    g_mutex_lock(&context.mutex);
    while (!context.callback_entered && !context.emit_completed) {
        if (!g_cond_wait_until(&context.cond, &context.mutex, deadline)) {
            break;
        }
    }
    gboolean callback_entered = context.callback_entered;
    gboolean emit_completed = context.emit_completed;
    g_mutex_unlock(&context.mutex);

    if (callback_entered && !emit_completed) {
        swift_gst_callback_registration_disconnect(registration);
    } else {
        status = SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_TIMEOUT;
    }

    g_mutex_lock(&context.mutex);
    context.release_callback = TRUE;
    g_cond_broadcast(&context.cond);
    g_mutex_unlock(&context.mutex);

    g_thread_join(thread);

    if (status != SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_OK) {
        swift_gst_callback_registration_disconnect(registration);
    }

    SwiftGstTestCallbackRegistrationRaceResult result =
        swift_gst_test_callback_registration_race_result(status, &context);
    g_cond_clear(&context.cond);
    g_mutex_clear(&context.mutex);
    gst_object_unref(element);
    return result;
}

SwiftGstTestBaseSinkOwnershipProbeResult swift_gst_test_base_sink_class_context_ownership_probe(
    const gchar* success_factory_name,
    const gchar* success_type_name,
    const gchar* duplicate_factory_type_name,
    const gchar* duplicate_type_factory_name
) {
    SwiftGstTestBaseSinkOwnershipProbeResult result = {0};

    SwiftGstBaseSinkCallbacks callbacks = swift_gst_test_base_sink_callbacks();

    SwiftGstTestBaseSinkContext* success_context = g_new0(SwiftGstTestBaseSinkContext, 1);
    swift_gst_test_base_sink_context_init(success_context);
    result.success_registration_succeeded = swift_gst_test_base_sink_register(
        success_factory_name,
        success_type_name,
        success_context,
        &callbacks
    );
    result.success_context = swift_gst_test_base_sink_counts(success_context);

    SwiftGstTestBaseSinkContext* duplicate_factory_context = g_new0(SwiftGstTestBaseSinkContext, 1);
    swift_gst_test_base_sink_context_init(duplicate_factory_context);
    result.duplicate_factory_registration_failed = !swift_gst_test_base_sink_register(
        success_factory_name,
        duplicate_factory_type_name,
        duplicate_factory_context,
        &callbacks
    );
    result.duplicate_factory_context = swift_gst_test_base_sink_counts(duplicate_factory_context);

    SwiftGstTestBaseSinkContext* duplicate_type_context = g_new0(SwiftGstTestBaseSinkContext, 1);
    swift_gst_test_base_sink_context_init(duplicate_type_context);
    result.duplicate_type_registration_failed = !swift_gst_test_base_sink_register(
        duplicate_type_factory_name,
        success_type_name,
        duplicate_type_context,
        &callbacks
    );
    result.duplicate_type_context = swift_gst_test_base_sink_counts(duplicate_type_context);

    return result;
}

SwiftGstTestBaseSinkMissingInstanceProbeResult swift_gst_test_base_sink_missing_instance_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseSinkMissingInstanceProbeResult result = {0};

    SwiftGstBaseSinkCallbacks callbacks = swift_gst_test_base_sink_callbacks();
    callbacks.create_instance = NULL;

    SwiftGstTestBaseSinkContext* context = g_new0(SwiftGstTestBaseSinkContext, 1);
    swift_gst_test_base_sink_context_init(context);
    result.registration_succeeded = swift_gst_test_base_sink_register(
        factory_name,
        type_name,
        context,
        &callbacks
    );

    if (!result.registration_succeeded) {
        result.callback_counts = swift_gst_test_base_sink_counts(context);
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        result.callback_counts = swift_gst_test_base_sink_counts(context);
        return result;
    }

    result.element_created = TRUE;

    GstBaseSink* sink = GST_BASE_SINK(element);
    GstBaseSinkClass* sink_class = GST_BASE_SINK_GET_CLASS(sink);
    GstBuffer* buffer = gst_buffer_new_allocate(NULL, 1, NULL);

    swift_gst_test_base_sink_set_missing_probe_context(context);

    gboolean start_result = sink_class && sink_class->start ? sink_class->start(sink) : FALSE;
    GstFlowReturn render_result = sink_class && sink_class->render && buffer
        ? sink_class->render(sink, buffer)
        : GST_FLOW_ERROR;
    gboolean stop_result = sink_class && sink_class->stop ? sink_class->stop(sink) : FALSE;

    swift_gst_test_base_sink_set_missing_probe_context(NULL);

    if (buffer) {
        gst_buffer_unref(buffer);
    }
    gst_object_unref(element);

    result.start_returned_false = !start_result;
    result.render_returned_flow_error = render_result == GST_FLOW_ERROR;
    result.stop_returned_true = stop_result;
    result.callback_counts = swift_gst_test_base_sink_counts(context);
    return result;
}

SwiftGstTestBaseTransformOwnershipProbeResult swift_gst_test_base_transform_class_context_ownership_probe(
    const gchar* success_factory_name,
    const gchar* success_type_name,
    const gchar* duplicate_factory_type_name,
    const gchar* duplicate_type_factory_name
) {
    SwiftGstTestBaseTransformOwnershipProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks = swift_gst_test_base_transform_callbacks();

    SwiftGstTestBaseTransformContext* success_context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(success_context);
    result.success_registration_succeeded = swift_gst_test_base_transform_register(
        success_factory_name,
        success_type_name,
        success_context,
        &callbacks
    );
    result.success_context = swift_gst_test_base_transform_counts(success_context);

    SwiftGstTestBaseTransformContext* duplicate_factory_context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(duplicate_factory_context);
    result.duplicate_factory_registration_failed = !swift_gst_test_base_transform_register(
        success_factory_name,
        duplicate_factory_type_name,
        duplicate_factory_context,
        &callbacks
    );
    result.duplicate_factory_context = swift_gst_test_base_transform_counts(duplicate_factory_context);

    SwiftGstTestBaseTransformContext* duplicate_type_context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(duplicate_type_context);
    result.duplicate_type_registration_failed = !swift_gst_test_base_transform_register(
        duplicate_type_factory_name,
        success_type_name,
        duplicate_type_context,
        &callbacks
    );
    result.duplicate_type_context = swift_gst_test_base_transform_counts(duplicate_type_context);

    return result;
}

SwiftGstTestBaseTransformBufferRejectionProbeResult swift_gst_test_base_transform_buffer_rejection_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseTransformBufferRejectionProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks = swift_gst_test_base_transform_callbacks();

    SwiftGstTestBaseTransformContext* context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(context);
    result.registration_succeeded = swift_gst_test_base_transform_register(
        factory_name,
        type_name,
        context,
        &callbacks
    );

    if (!result.registration_succeeded) {
        result.callback_counts = swift_gst_test_base_transform_counts(context);
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        result.callback_counts = swift_gst_test_base_transform_counts(context);
        return result;
    }

    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);

    GstFlowReturn nil_buffer_result = transform_class && transform_class->transform_ip
        ? transform_class->transform_ip(transform, NULL)
        : GST_FLOW_ERROR;

    GstBuffer* buffer = gst_buffer_new_allocate(NULL, 1, NULL);
    GstBuffer* extra_ref = buffer ? gst_buffer_ref(buffer) : NULL;
    GstFlowReturn non_writable_result = transform_class && transform_class->transform_ip && buffer
        ? transform_class->transform_ip(transform, buffer)
        : GST_FLOW_ERROR;

    if (extra_ref) {
        gst_buffer_unref(extra_ref);
    }
    if (buffer) {
        gst_buffer_unref(buffer);
    }
    gst_object_unref(element);

    result.nil_buffer_returned_flow_error = nil_buffer_result == GST_FLOW_ERROR;
    result.non_writable_buffer_returned_flow_error = non_writable_result == GST_FLOW_ERROR;
    result.callback_counts = swift_gst_test_base_transform_counts(context);
    return result;
}

SwiftGstTestBaseTransformMissingInstanceProbeResult swift_gst_test_base_transform_missing_instance_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseTransformMissingInstanceProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks = swift_gst_test_base_transform_callbacks();
    callbacks.create_instance = NULL;

    SwiftGstTestBaseTransformContext* context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(context);
    result.registration_succeeded = swift_gst_test_base_transform_register(
        factory_name,
        type_name,
        context,
        &callbacks
    );

    if (!result.registration_succeeded) {
        result.callback_counts = swift_gst_test_base_transform_counts(context);
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        result.callback_counts = swift_gst_test_base_transform_counts(context);
        return result;
    }

    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);
    GstCaps* caps = gst_caps_from_string("video/x-raw");
    GstBuffer* buffer = gst_buffer_new_allocate(NULL, 1, NULL);

    swift_gst_test_base_transform_set_missing_probe_context(context);

    gboolean start_result = transform_class && transform_class->start
        ? transform_class->start(transform)
        : FALSE;
    gboolean set_caps_result = transform_class && transform_class->set_caps && caps
        ? transform_class->set_caps(transform, caps, caps)
        : FALSE;
    GstFlowReturn transform_ip_result = transform_class && transform_class->transform_ip && buffer
        ? transform_class->transform_ip(transform, buffer)
        : GST_FLOW_ERROR;
    gboolean stop_result = transform_class && transform_class->stop
        ? transform_class->stop(transform)
        : FALSE;

    swift_gst_test_base_transform_set_missing_probe_context(NULL);

    if (buffer) {
        gst_buffer_unref(buffer);
    }
    if (caps) {
        gst_caps_unref(caps);
    }
    gst_object_unref(element);

    result.start_returned_false = !start_result;
    result.set_caps_returned_false = !set_caps_result;
    result.transform_ip_returned_flow_error = transform_ip_result == GST_FLOW_ERROR;
    result.stop_returned_true = stop_result;
    result.callback_counts = swift_gst_test_base_transform_counts(context);
    return result;
}

SwiftGstTestProbe* swift_gst_test_install_bus_error_after_buffers(
    GstElement* pipeline,
    const gchar* element_name,
    const gchar* pad_name,
    guint after_buffers,
    const gchar* message,
    const gchar* debug
) {
    return swift_gst_test_install_probe_after_buffers(
        pipeline,
        element_name,
        pad_name,
        after_buffers,
        SWIFT_GST_TEST_PROBE_ERROR,
        message,
        debug,
        NULL
    );
}

SwiftGstTestProbe* swift_gst_test_install_marker_after_buffers(
    GstElement* pipeline,
    const gchar* element_name,
    const gchar* pad_name,
    guint after_buffers,
    const gchar* marker
) {
    return swift_gst_test_install_probe_after_buffers(
        pipeline,
        element_name,
        pad_name,
        after_buffers,
        SWIFT_GST_TEST_PROBE_MARKER,
        NULL,
        NULL,
        marker
    );
}

guint swift_gst_test_probe_buffer_count(SwiftGstTestProbe* probe) {
    if (!probe) {
        return 0;
    }

    g_mutex_lock(&probe->mutex);
    guint count = probe->buffer_count;
    g_mutex_unlock(&probe->mutex);
    return count;
}

gboolean swift_gst_test_probe_acknowledged(SwiftGstTestProbe* probe) {
    if (!probe) {
        return FALSE;
    }

    g_mutex_lock(&probe->mutex);
    gboolean acknowledged = probe->acknowledged;
    g_mutex_unlock(&probe->mutex);
    return acknowledged;
}

void swift_gst_test_probe_free(SwiftGstTestProbe* probe) {
    if (!probe) {
        return;
    }

    if (probe->pad && probe->probe_id != 0) {
        gst_pad_remove_probe(probe->pad, probe->probe_id);
    }

    if (probe->pad) {
        gst_object_unref(probe->pad);
    }
    if (probe->pipeline) {
        gst_object_unref(probe->pipeline);
    }

    g_free(probe->message);
    g_free(probe->debug);
    g_free(probe->marker);
    g_mutex_clear(&probe->mutex);
    g_free(probe);
}

gboolean swift_gst_test_post_bus_error(
    GstElement* pipeline,
    const gchar* message,
    const gchar* debug
) {
    if (!pipeline) {
        return FALSE;
    }

    GError* error = g_error_new_literal(
        g_quark_from_static_string("swift-gst-test"),
        1,
        message ? message : "Injected reliable packet test error"
    );
    GstMessage* gst_message = gst_message_new_error(
        GST_OBJECT(pipeline),
        error,
        debug ? debug : NULL
    );
    gboolean posted = gst_element_post_message(pipeline, gst_message);
    g_error_free(error);
    return posted;
}

gboolean swift_gst_test_post_element_marker(GstElement* pipeline, const gchar* marker) {
    if (!pipeline) {
        return FALSE;
    }

    GstStructure* structure = gst_structure_new(
        "swift-gst-test-marker",
        "marker",
        G_TYPE_STRING,
        marker ? marker : "swift-gst-test-marker",
        NULL
    );
    GstMessage* message = gst_message_new_element(GST_OBJECT(pipeline), structure);
    return gst_element_post_message(pipeline, message);
}

gboolean swift_gst_test_signal_handler_is_connected(GObject* object, gulong handler_id) {
    if (!object || handler_id == 0) {
        return FALSE;
    }

    return g_signal_handler_is_connected(object, handler_id);
}

guint swift_gst_test_signal_handler_count(GObject* object, const gchar* signal_name) {
    if (!object || !signal_name) {
        return 0;
    }

    guint signal_id = g_signal_lookup(signal_name, G_OBJECT_TYPE(object));
    if (signal_id == 0) {
        return 0;
    }

    guint count = g_signal_handlers_block_matched(
        object,
        G_SIGNAL_MATCH_ID,
        signal_id,
        0,
        NULL,
        NULL,
        NULL
    );

    if (count > 0) {
        g_signal_handlers_unblock_matched(
            object,
            G_SIGNAL_MATCH_ID,
            signal_id,
            0,
            NULL,
            NULL,
            NULL
        );
    }

    return count;
}

guint swift_gst_test_buffer_refcount(GstBuffer* buffer) {
    if (!buffer) {
        return 0;
    }

    return GST_MINI_OBJECT_REFCOUNT_VALUE(buffer);
}

gchar* swift_gst_test_sample_caps_string(GstSample* sample) {
    if (!sample) {
        return NULL;
    }

    GstCaps* caps = gst_sample_get_caps(sample);
    if (!caps) {
        return NULL;
    }

    return gst_caps_to_string(caps);
}

gchar* swift_gst_test_appsink_first_sample_caps_string(GstAppSink* appsink, GstClockTime timeout) {
    if (!appsink) {
        return NULL;
    }

    GstSample* sample = gst_app_sink_try_pull_sample(appsink, timeout);
    if (!sample) {
        return NULL;
    }

    gchar* caps = swift_gst_test_sample_caps_string(sample);
    gst_sample_unref(sample);
    return caps;
}

gboolean swift_gst_test_bus_pop_marker(GstBus* bus, const gchar* marker, GstClockTime timeout) {
    if (!bus || !marker) {
        return FALSE;
    }

    gint64 deadline = g_get_monotonic_time() + (gint64)(timeout / 1000);

    while (g_get_monotonic_time() <= deadline) {
        gint64 remaining_us = deadline - g_get_monotonic_time();
        GstClockTime poll_timeout = remaining_us > 0
            ? (GstClockTime)remaining_us * 1000
            : 0;
        if (poll_timeout > 10 * GST_MSECOND) {
            poll_timeout = 10 * GST_MSECOND;
        }

        GstMessage* message = gst_bus_timed_pop_filtered(
            bus,
            poll_timeout,
            GST_MESSAGE_ELEMENT | GST_MESSAGE_ERROR | GST_MESSAGE_EOS
        );
        if (!message) {
            continue;
        }

        gboolean matched = FALSE;
        if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_ELEMENT) {
            const GstStructure* structure = gst_message_get_structure(message);
            if (structure && gst_structure_has_name(structure, "swift-gst-test-marker")) {
                const gchar* value = gst_structure_get_string(structure, "marker");
                matched = value && g_strcmp0(value, marker) == 0;
            }
        }

        gst_message_unref(message);

        if (matched) {
            return TRUE;
        }
    }

    return FALSE;
}
