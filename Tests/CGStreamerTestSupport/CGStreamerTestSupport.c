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
    guint transform_count;
} SwiftGstTestBaseTransformContext;

typedef struct {
    GMutex mutex;
    SwiftGstBaseTransformHookStatus status;
    gboolean value;
    gboolean query_caps_observed;
    gboolean query_needs_pool_observed;
    guint pools_before;
    guint pools_after;
    guint params_before;
    guint params_after;
    guint metas_before;
    guint metas_after;
    gboolean propose_decide_query_caps_observed;
    gboolean propose_query_caps_observed;
    gboolean filter_api_observed;
    gboolean transform_meta_api_observed;
} SwiftGstTestBaseTransformGeneralHookProbeContext;

typedef struct {
    GstBaseSink parent_instance;
    void* instance_context;
} SwiftGstTestNativeBaseSinkView;

typedef struct {
    GstBaseTransform parent_instance;
    void* instance_context;
} SwiftGstTestNativeBaseTransformView;

static GMutex swift_gst_test_base_sink_missing_probe_mutex;
static SwiftGstTestBaseSinkContext* swift_gst_test_base_sink_missing_probe_context = NULL;
static GMutex swift_gst_test_base_transform_missing_probe_mutex;
static GMutex swift_gst_test_base_transform_missing_probe_call_mutex;
static SwiftGstTestBaseTransformContext* swift_gst_test_base_transform_missing_probe_context = NULL;

typedef GstBuffer* (*SwiftGstBaseTransformTestOutputAllocatorFunc)(GstBuffer* input, gsize size);
extern void swift_gst_base_transform_test_set_output_allocator(
    SwiftGstBaseTransformTestOutputAllocatorFunc allocator
);

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

static SwiftGstTestBaseTransformOutOfPlaceCallbackCounts swift_gst_test_base_transform_out_of_place_counts(
    SwiftGstTestBaseTransformContext* context
) {
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts counts = {0};

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
    counts.transform_count = context->transform_count;
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

static GstFlowReturn swift_gst_test_base_transform(
    void* instance_context,
    GstBuffer* input,
    GstBuffer* output
) {
    (void)input;
    (void)output;

    SwiftGstTestBaseTransformContext* context =
        swift_gst_test_base_transform_callback_context(instance_context);
    if (!context) {
        return GST_FLOW_ERROR;
    }
    swift_gst_test_base_transform_increment(context, &context->transform_count);
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
        .mode = SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE,
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
        .transform = swift_gst_test_base_transform,
    };
    return callbacks;
}

static SwiftGstBaseTransformInfo swift_gst_test_base_transform_out_of_place_info(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstBaseTransformInfo info = swift_gst_test_base_transform_info(factory_name, type_name);
    info.mode = SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE;
    info.passthrough_on_same_caps = FALSE;
    info.transform_ip_on_passthrough = FALSE;
    return info;
}

static SwiftGstBaseTransformInfo swift_gst_test_base_transform_general_out_of_place_info(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstBaseTransformInfo info =
        swift_gst_test_base_transform_out_of_place_info(factory_name, type_name);
    info.mode = SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE_GENERAL;
    return info;
}

static SwiftGstBaseTransformCallbacks swift_gst_test_base_transform_out_of_place_callbacks(void) {
    SwiftGstBaseTransformCallbacks callbacks = swift_gst_test_base_transform_callbacks();
    callbacks.transform_ip = NULL;
    callbacks.transform = swift_gst_test_base_transform;
    return callbacks;
}

static SwiftGstBaseTransformCapsResult swift_gst_test_base_transform_caps_use_default(
    void* instance_context,
    GstPadDirection direction,
    GstCaps* caps,
    GstCaps* filter
) {
    (void)instance_context;
    (void)direction;
    (void)caps;
    (void)filter;

    SwiftGstBaseTransformCapsResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .caps = NULL,
    };
    return result;
}

static SwiftGstBaseTransformSizeResult swift_gst_test_base_transform_unit_size_use_default(
    void* instance_context,
    GstCaps* caps
) {
    (void)instance_context;
    (void)caps;

    SwiftGstBaseTransformSizeResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .size = 0,
    };
    return result;
}

static SwiftGstBaseTransformSizeResult swift_gst_test_base_transform_size_use_default(
    void* instance_context,
    GstPadDirection direction,
    GstCaps* caps,
    gsize size,
    GstCaps* other_caps
) {
    (void)instance_context;
    (void)direction;
    (void)caps;
    (void)size;
    (void)other_caps;

    SwiftGstBaseTransformSizeResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .size = 0,
    };
    return result;
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_bool_use_default(
    void* instance_context,
    GstQuery* query
) {
    (void)instance_context;
    (void)query;

    SwiftGstBaseTransformBoolResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .value = FALSE,
    };
    return result;
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_propose_allocation_use_default(
    void* instance_context,
    GstQuery* decide_query,
    GstQuery* query
) {
    (void)instance_context;
    (void)decide_query;
    (void)query;

    SwiftGstBaseTransformBoolResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .value = FALSE,
    };
    return result;
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_filter_meta_use_default(
    void* instance_context,
    GstQuery* query,
    GType api,
    const GstStructure* params
) {
    (void)instance_context;
    (void)query;
    (void)api;
    (void)params;

    SwiftGstBaseTransformBoolResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .value = FALSE,
    };
    return result;
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_copy_metadata_use_default(
    void* instance_context,
    GstBuffer* input,
    GstBuffer* output
) {
    (void)instance_context;
    (void)input;
    (void)output;

    SwiftGstBaseTransformBoolResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .value = FALSE,
    };
    return result;
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_transform_meta_use_default(
    void* instance_context,
    GstBuffer* output,
    GstMeta* metadata,
    GstBuffer* input
) {
    (void)instance_context;
    (void)output;
    (void)metadata;
    (void)input;

    SwiftGstBaseTransformBoolResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
        .value = FALSE,
    };
    return result;
}

static SwiftGstBaseTransformCallbacks swift_gst_test_base_transform_general_out_of_place_callbacks(void) {
    SwiftGstBaseTransformCallbacks callbacks = swift_gst_test_base_transform_out_of_place_callbacks();
    callbacks.transform_caps = swift_gst_test_base_transform_caps_use_default;
    callbacks.fixate_caps = swift_gst_test_base_transform_caps_use_default;
    callbacks.get_unit_size = swift_gst_test_base_transform_unit_size_use_default;
    callbacks.transform_size = swift_gst_test_base_transform_size_use_default;
    callbacks.decide_allocation = swift_gst_test_base_transform_bool_use_default;
    callbacks.propose_allocation = swift_gst_test_base_transform_propose_allocation_use_default;
    callbacks.filter_meta = swift_gst_test_base_transform_filter_meta_use_default;
    callbacks.copy_metadata = swift_gst_test_base_transform_copy_metadata_use_default;
    callbacks.transform_meta = swift_gst_test_base_transform_transform_meta_use_default;
    return callbacks;
}

static void swift_gst_test_base_transform_general_hook_probe_context_init(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context
) {
    if (context == NULL) {
        return;
    }

    g_mutex_init(&context->mutex);
    context->status = SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE;
    context->value = TRUE;
}

static void swift_gst_test_base_transform_general_hook_probe_set_result(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context,
    SwiftGstBaseTransformHookStatus status,
    gboolean value
) {
    if (context == NULL) {
        return;
    }

    g_mutex_lock(&context->mutex);
    context->status = status;
    context->value = value;
    g_mutex_unlock(&context->mutex);
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_general_hook_probe_result(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context
) {
    SwiftGstBaseTransformBoolResult result = {
        .status = SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
        .value = FALSE,
    };
    if (context == NULL) {
        return result;
    }

    g_mutex_lock(&context->mutex);
    result.status = context->status;
    result.value = context->value;
    g_mutex_unlock(&context->mutex);
    return result;
}

static void* swift_gst_test_base_transform_general_hook_probe_create_instance(void* class_context) {
    return class_context;
}

static void swift_gst_test_base_transform_general_hook_probe_destroy_instance(void* instance_context) {
    (void)instance_context;
}

static void swift_gst_test_base_transform_general_hook_probe_retain(void* data) {
    (void)data;
}

static void swift_gst_test_base_transform_general_hook_probe_release(void* data) {
    (void)data;
}

static gboolean swift_gst_test_base_transform_general_hook_probe_lifecycle(void* instance_context) {
    return instance_context != NULL;
}

static gboolean swift_gst_test_base_transform_general_hook_probe_set_caps(
    void* instance_context,
    GstCaps* input_caps,
    GstCaps* output_caps
) {
    (void)input_caps;
    (void)output_caps;
    return instance_context != NULL;
}

static GstFlowReturn swift_gst_test_base_transform_general_hook_probe_transform(
    void* instance_context,
    GstBuffer* input,
    GstBuffer* output
) {
    (void)input;
    (void)output;
    return instance_context != NULL ? GST_FLOW_OK : GST_FLOW_ERROR;
}

static void swift_gst_test_base_transform_general_hook_probe_record_decide_query(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context,
    GstQuery* query
) {
    if (context == NULL || query == NULL) {
        return;
    }

    GstCaps* caps = NULL;
    gboolean needs_pool = FALSE;
    gst_query_parse_allocation(query, &caps, &needs_pool);
    guint pools_before = gst_query_get_n_allocation_pools(query);
    guint params_before = gst_query_get_n_allocation_params(query);
    guint metas_before = gst_query_get_n_allocation_metas(query);

    gst_query_add_allocation_pool(query, NULL, 64, 1, 3);
    GstAllocationParams params;
    gst_allocation_params_init(&params);
    params.align = 7;
    params.prefix = 3;
    params.padding = 5;
    gst_query_add_allocation_param(query, NULL, &params);
    gst_query_add_allocation_meta(query, gst_parent_buffer_meta_api_get_type(), NULL);

    g_mutex_lock(&context->mutex);
    context->query_caps_observed = caps != NULL;
    context->query_needs_pool_observed = needs_pool;
    context->pools_before = pools_before;
    context->pools_after = gst_query_get_n_allocation_pools(query);
    context->params_before = params_before;
    context->params_after = gst_query_get_n_allocation_params(query);
    context->metas_before = metas_before;
    context->metas_after = gst_query_get_n_allocation_metas(query);
    g_mutex_unlock(&context->mutex);
}

static gboolean swift_gst_test_base_transform_general_hook_probe_allocation_caps_observed(
    GstQuery* query
) {
    if (query == NULL) {
        return FALSE;
    }

    GstCaps* caps = NULL;
    gst_query_parse_allocation(query, &caps, NULL);
    return caps != NULL;
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_general_hook_probe_decide_allocation(
    void* instance_context,
    GstQuery* query
) {
    SwiftGstTestBaseTransformGeneralHookProbeContext* context =
        (SwiftGstTestBaseTransformGeneralHookProbeContext*)instance_context;
    swift_gst_test_base_transform_general_hook_probe_record_decide_query(context, query);
    return swift_gst_test_base_transform_general_hook_probe_result(context);
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_general_hook_probe_propose_allocation(
    void* instance_context,
    GstQuery* decide_query,
    GstQuery* query
) {
    SwiftGstTestBaseTransformGeneralHookProbeContext* context =
        (SwiftGstTestBaseTransformGeneralHookProbeContext*)instance_context;
    if (context != NULL) {
        g_mutex_lock(&context->mutex);
        context->propose_decide_query_caps_observed =
            swift_gst_test_base_transform_general_hook_probe_allocation_caps_observed(decide_query);
        context->propose_query_caps_observed =
            swift_gst_test_base_transform_general_hook_probe_allocation_caps_observed(query);
        g_mutex_unlock(&context->mutex);
    }
    return swift_gst_test_base_transform_general_hook_probe_result(context);
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_general_hook_probe_filter_meta(
    void* instance_context,
    GstQuery* query,
    GType api,
    const GstStructure* params
) {
    (void)query;
    (void)params;

    SwiftGstTestBaseTransformGeneralHookProbeContext* context =
        (SwiftGstTestBaseTransformGeneralHookProbeContext*)instance_context;
    if (context != NULL) {
        g_mutex_lock(&context->mutex);
        context->filter_api_observed = api == gst_parent_buffer_meta_api_get_type();
        g_mutex_unlock(&context->mutex);
    }
    return swift_gst_test_base_transform_general_hook_probe_result(context);
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_general_hook_probe_copy_metadata(
    void* instance_context,
    GstBuffer* input,
    GstBuffer* output
) {
    SwiftGstTestBaseTransformGeneralHookProbeContext* context =
        input != NULL && output != NULL
            ? (SwiftGstTestBaseTransformGeneralHookProbeContext*)instance_context
            : NULL;
    return swift_gst_test_base_transform_general_hook_probe_result(context);
}

static SwiftGstBaseTransformBoolResult swift_gst_test_base_transform_general_hook_probe_transform_meta(
    void* instance_context,
    GstBuffer* output,
    GstMeta* metadata,
    GstBuffer* input
) {
    (void)input;
    (void)output;

    SwiftGstTestBaseTransformGeneralHookProbeContext* context =
        (SwiftGstTestBaseTransformGeneralHookProbeContext*)instance_context;
    if (context != NULL && metadata != NULL && metadata->info != NULL) {
        g_mutex_lock(&context->mutex);
        context->transform_meta_api_observed =
            metadata->info->api == gst_parent_buffer_meta_api_get_type();
        g_mutex_unlock(&context->mutex);
    }
    return swift_gst_test_base_transform_general_hook_probe_result(context);
}

static SwiftGstBaseTransformCallbacks swift_gst_test_base_transform_general_hook_probe_callbacks(void) {
    SwiftGstBaseTransformCallbacks callbacks = {0};
    callbacks.create_instance = swift_gst_test_base_transform_general_hook_probe_create_instance;
    callbacks.destroy_instance = swift_gst_test_base_transform_general_hook_probe_destroy_instance;
    callbacks.start = swift_gst_test_base_transform_general_hook_probe_lifecycle;
    callbacks.stop = swift_gst_test_base_transform_general_hook_probe_lifecycle;
    callbacks.set_caps = swift_gst_test_base_transform_general_hook_probe_set_caps;
    callbacks.transform = swift_gst_test_base_transform_general_hook_probe_transform;
    callbacks.transform_caps = swift_gst_test_base_transform_caps_use_default;
    callbacks.fixate_caps = swift_gst_test_base_transform_caps_use_default;
    callbacks.get_unit_size = swift_gst_test_base_transform_unit_size_use_default;
    callbacks.transform_size = swift_gst_test_base_transform_size_use_default;
    callbacks.decide_allocation = swift_gst_test_base_transform_general_hook_probe_decide_allocation;
    callbacks.propose_allocation = swift_gst_test_base_transform_general_hook_probe_propose_allocation;
    callbacks.filter_meta = swift_gst_test_base_transform_general_hook_probe_filter_meta;
    callbacks.copy_metadata = swift_gst_test_base_transform_general_hook_probe_copy_metadata;
    callbacks.transform_meta = swift_gst_test_base_transform_general_hook_probe_transform_meta;
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

static gboolean swift_gst_test_base_transform_out_of_place_register(
    const gchar* factory_name,
    const gchar* type_name,
    SwiftGstTestBaseTransformContext* context,
    const SwiftGstBaseTransformCallbacks* callbacks
) {
    SwiftGstBaseTransformInfo info =
        swift_gst_test_base_transform_out_of_place_info(factory_name, type_name);
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

gboolean swift_gst_test_element_factory_has_plugin_owner(const gchar* factory_name) {
    if (!factory_name) {
        return FALSE;
    }

    GstElementFactory* factory = gst_element_factory_find(factory_name);
    if (!factory) {
        return FALSE;
    }

    const gchar* plugin_name = gst_plugin_feature_get_plugin_name(GST_PLUGIN_FEATURE(factory));
    gboolean result = plugin_name != NULL && plugin_name[0] != '\0';
    gst_object_unref(factory);
    return result;
}

gboolean swift_gst_test_element_factory_plugin_name_matches(
    const gchar* factory_name,
    const gchar* expected_plugin_name
) {
    if (!factory_name || !expected_plugin_name) {
        return FALSE;
    }

    GstElementFactory* factory = gst_element_factory_find(factory_name);
    if (!factory) {
        return FALSE;
    }

    const gchar* plugin_name = gst_plugin_feature_get_plugin_name(GST_PLUGIN_FEATURE(factory));
    gboolean result = g_strcmp0(plugin_name, expected_plugin_name) == 0;
    gst_object_unref(factory);
    return result;
}

GLogLevelFlags swift_gst_test_enable_fatal_criticals(void) {
    GLogLevelFlags previous = g_log_set_always_fatal(G_LOG_FATAL_MASK);
    g_log_set_always_fatal(previous | G_LOG_LEVEL_CRITICAL);
    return previous;
}

void swift_gst_test_restore_fatal_mask(GLogLevelFlags previous) {
    g_log_set_always_fatal(previous);
}

GParamFlags swift_gst_test_param_mutable_playing(void) {
    return GST_PARAM_MUTABLE_PLAYING;
}

guint swift_gst_test_element_property_id(GstElement* element, const gchar* property_name) {
    if (!element || !property_name) {
        return 0;
    }

    GObjectClass* object_class = G_OBJECT_GET_CLASS(element);
    if (!object_class) {
        return 0;
    }

    GParamSpec* spec = g_object_class_find_property(object_class, property_name);
    return spec ? spec->param_id : 0;
}

static void** swift_gst_test_native_instance_context_slot(
    GstElement* element,
    gboolean is_base_transform
) {
    if (!element) {
        return NULL;
    }

    if (is_base_transform) {
        if (!GST_IS_BASE_TRANSFORM(element)) {
            return NULL;
        }

        SwiftGstTestNativeBaseTransformView* view = (SwiftGstTestNativeBaseTransformView*)element;
        return &view->instance_context;
    }

    if (!GST_IS_BASE_SINK(element)) {
        return NULL;
    }

    SwiftGstTestNativeBaseSinkView* view = (SwiftGstTestNativeBaseSinkView*)element;
    return &view->instance_context;
}

SwiftGstTestNativePropertyDefaultsProbeResult swift_gst_test_native_property_missing_instance_defaults_probe(
    GstElement* element,
    gboolean is_base_transform,
    const gchar* bool_name,
    const gchar* int_name,
    const gchar* double_name,
    const gchar* string_name,
    const gchar* enum_name
) {
    SwiftGstTestNativePropertyDefaultsProbeResult result = {0};
    void** instance_context_slot =
        swift_gst_test_native_instance_context_slot(element, is_base_transform);
    if (!instance_context_slot
        || !bool_name
        || !int_name
        || !double_name
        || !string_name
        || !enum_name) {
        return result;
    }

    void* saved_instance_context = *instance_context_slot;
    *instance_context_slot = NULL;

    g_object_get(
        G_OBJECT(element),
        bool_name,
        &result.bool_value,
        int_name,
        &result.int_value,
        double_name,
        &result.double_value,
        string_name,
        &result.string_value,
        enum_name,
        &result.enum_value,
        NULL
    );

    *instance_context_slot = saved_instance_context;
    result.success = TRUE;
    return result;
}

void swift_gst_test_native_property_defaults_probe_result_clear(
    SwiftGstTestNativePropertyDefaultsProbeResult* result
) {
    if (!result) {
        return;
    }

    g_clear_pointer(&result->string_value, g_free);
    g_clear_pointer(&result->enum_value, g_free);
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

    g_mutex_lock(&swift_gst_test_base_transform_missing_probe_call_mutex);
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
    g_mutex_unlock(&swift_gst_test_base_transform_missing_probe_call_mutex);

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

SwiftGstTestBaseTransformOutOfPlaceOwnershipProbeResult swift_gst_test_base_transform_out_of_place_class_context_ownership_probe(
    const gchar* success_factory_name,
    const gchar* success_type_name,
    const gchar* duplicate_factory_type_name,
    const gchar* duplicate_type_factory_name
) {
    SwiftGstTestBaseTransformOutOfPlaceOwnershipProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();

    SwiftGstTestBaseTransformContext* success_context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(success_context);
    result.success_registration_succeeded = swift_gst_test_base_transform_out_of_place_register(
        success_factory_name,
        success_type_name,
        success_context,
        &callbacks
    );
    result.success_context = swift_gst_test_base_transform_out_of_place_counts(success_context);

    SwiftGstTestBaseTransformContext* duplicate_factory_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(duplicate_factory_context);
    result.duplicate_factory_registration_failed = !swift_gst_test_base_transform_out_of_place_register(
        success_factory_name,
        duplicate_factory_type_name,
        duplicate_factory_context,
        &callbacks
    );
    result.duplicate_factory_context =
        swift_gst_test_base_transform_out_of_place_counts(duplicate_factory_context);

    SwiftGstTestBaseTransformContext* duplicate_type_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(duplicate_type_context);
    result.duplicate_type_registration_failed = !swift_gst_test_base_transform_out_of_place_register(
        duplicate_type_factory_name,
        success_type_name,
        duplicate_type_context,
        &callbacks
    );
    result.duplicate_type_context =
        swift_gst_test_base_transform_out_of_place_counts(duplicate_type_context);

    return result;
}

SwiftGstTestBaseTransformOutOfPlaceMissingInstanceProbeResult swift_gst_test_base_transform_out_of_place_missing_instance_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseTransformOutOfPlaceMissingInstanceProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    callbacks.create_instance = NULL;

    SwiftGstTestBaseTransformContext* context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(context);
    result.registration_succeeded = swift_gst_test_base_transform_out_of_place_register(
        factory_name,
        type_name,
        context,
        &callbacks
    );

    if (!result.registration_succeeded) {
        result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
        return result;
    }

    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);
    GstCaps* caps = gst_caps_from_string("video/x-raw");
    GstBuffer* input = gst_buffer_new_allocate(NULL, 1, NULL);
    GstBuffer* output = gst_buffer_new_allocate(NULL, 1, NULL);

    g_mutex_lock(&swift_gst_test_base_transform_missing_probe_call_mutex);
    swift_gst_test_base_transform_set_missing_probe_context(context);

    gboolean start_result = transform_class && transform_class->start
        ? transform_class->start(transform)
        : FALSE;
    gboolean set_caps_result = transform_class && transform_class->set_caps && caps
        ? transform_class->set_caps(transform, caps, caps)
        : FALSE;
    GstFlowReturn transform_result = transform_class && transform_class->transform && input && output
        ? transform_class->transform(transform, input, output)
        : GST_FLOW_ERROR;
    gboolean stop_result = transform_class && transform_class->stop
        ? transform_class->stop(transform)
        : FALSE;

    swift_gst_test_base_transform_set_missing_probe_context(NULL);
    g_mutex_unlock(&swift_gst_test_base_transform_missing_probe_call_mutex);

    if (output) {
        gst_buffer_unref(output);
    }
    if (input) {
        gst_buffer_unref(input);
    }
    if (caps) {
        gst_caps_unref(caps);
    }
    gst_object_unref(element);

    result.start_returned_false = !start_result;
    result.set_caps_returned_false = !set_caps_result;
    result.transform_returned_flow_error = transform_result == GST_FLOW_ERROR;
    result.stop_returned_true = stop_result;
    result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
    return result;
}

SwiftGstTestBaseTransformOutOfPlaceOutputAllocationProbeResult swift_gst_test_base_transform_out_of_place_output_allocation_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseTransformOutOfPlaceOutputAllocationProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    SwiftGstTestBaseTransformContext* context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(context);
    result.registration_succeeded = swift_gst_test_base_transform_out_of_place_register(
        factory_name,
        type_name,
        context,
        &callbacks
    );

    if (!result.registration_succeeded) {
        result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
        return result;
    }

    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);
    GstBuffer* input = gst_buffer_new_allocate(NULL, 8, NULL);
    GstBuffer* output = NULL;
    if (input) {
        GST_BUFFER_PTS(input) = 12345;
        GST_BUFFER_DURATION(input) = 67890;
        result.input_size = gst_buffer_get_size(input);
    }

    GstFlowReturn prepare_result = transform_class && transform_class->prepare_output_buffer && input
        ? transform_class->prepare_output_buffer(transform, input, &output)
        : GST_FLOW_ERROR;
    result.prepare_output_returned_ok = prepare_result == GST_FLOW_OK;

    if (output) {
        result.output_size = gst_buffer_get_size(output);
        result.output_is_distinct_from_input = output != input;
        result.output_is_writable = gst_buffer_is_writable(output);
        result.pts_preserved = GST_BUFFER_PTS(output) == GST_BUFFER_PTS(input);
        result.duration_preserved = GST_BUFFER_DURATION(output) == GST_BUFFER_DURATION(input);
    }

    GstFlowReturn transform_result = transform_class && transform_class->transform && input && output
        ? transform_class->transform(transform, input, output)
        : GST_FLOW_ERROR;
    result.transform_returned_ok = transform_result == GST_FLOW_OK;

    if (output) {
        gst_buffer_unref(output);
    }
    if (input) {
        gst_buffer_unref(input);
    }
    gst_object_unref(element);

    result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
    return result;
}

static GstBuffer* swift_gst_test_base_transform_failing_allocator(GstBuffer* input, gsize size) {
    (void)input;
    (void)size;
    return NULL;
}

SwiftGstTestBaseTransformOutOfPlaceAllocationFailureProbeResult swift_gst_test_base_transform_out_of_place_allocation_failure_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseTransformOutOfPlaceAllocationFailureProbeResult result = {0};

    SwiftGstBaseTransformCallbacks callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    SwiftGstTestBaseTransformContext* context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(context);
    result.registration_succeeded = swift_gst_test_base_transform_out_of_place_register(
        factory_name,
        type_name,
        context,
        &callbacks
    );

    if (!result.registration_succeeded) {
        result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
        return result;
    }

    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);
    GstBuffer* input = gst_buffer_new_allocate(NULL, 8, NULL);
    GstBuffer* output = NULL;

    swift_gst_base_transform_test_set_output_allocator(swift_gst_test_base_transform_failing_allocator);
    GstFlowReturn prepare_result = transform_class && transform_class->prepare_output_buffer && input
        ? transform_class->prepare_output_buffer(transform, input, &output)
        : GST_FLOW_ERROR;
    swift_gst_base_transform_test_set_output_allocator(NULL);

    result.prepare_output_returned_flow_error = prepare_result == GST_FLOW_ERROR;
    result.transform_not_called = context->transform_count == 0;

    if (output) {
        gst_buffer_unref(output);
    }
    if (input) {
        gst_buffer_unref(input);
    }
    gst_object_unref(element);

    result.callback_counts = swift_gst_test_base_transform_out_of_place_counts(context);
    return result;
}

static gboolean swift_gst_test_base_transform_register_info(
    SwiftGstBaseTransformInfo* info,
    SwiftGstBaseTransformCallbacks* callbacks,
    SwiftGstTestBaseTransformContext* context
) {
    gchar* error_message = NULL;
    gboolean registered = swift_gst_register_base_transform(
        info,
        callbacks,
        context,
        swift_gst_test_base_transform_retain,
        swift_gst_test_base_transform_release,
        &error_message
    );
    g_free(error_message);
    return registered;
}

SwiftGstTestBaseTransformModeValidationProbeResult swift_gst_test_base_transform_mode_validation_probe(void) {
    SwiftGstTestBaseTransformModeValidationProbeResult result = {0};

    SwiftGstTestBaseTransformContext* unknown_context = g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(unknown_context);
    SwiftGstBaseTransformInfo unknown_info = swift_gst_test_base_transform_info(
        "swiftoutofplace_c_mode_unknown",
        "SwiftGstTestOutOfPlaceCModeUnknownTransform"
    );
    unknown_info.mode = (SwiftGstBaseTransformMode)999;
    SwiftGstBaseTransformCallbacks unknown_callbacks = swift_gst_test_base_transform_callbacks();
    result.unknown_mode_registration_failed = !swift_gst_test_base_transform_register_info(
        &unknown_info,
        &unknown_callbacks,
        unknown_context
    );

    SwiftGstTestBaseTransformContext* in_place_without_transform_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(in_place_without_transform_context);
    SwiftGstBaseTransformInfo in_place_without_transform_info = swift_gst_test_base_transform_info(
        "swiftoutofplace_c_mode_inplace_without_transform",
        "SwiftGstTestOutOfPlaceCModeInPlaceWithoutTransform"
    );
    SwiftGstBaseTransformCallbacks in_place_without_transform_callbacks =
        swift_gst_test_base_transform_callbacks();
    in_place_without_transform_callbacks.transform = NULL;
    result.in_place_without_transform_registration_succeeded = swift_gst_test_base_transform_register_info(
        &in_place_without_transform_info,
        &in_place_without_transform_callbacks,
        in_place_without_transform_context
    );

    SwiftGstTestBaseTransformContext* in_place_without_transform_ip_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(in_place_without_transform_ip_context);
    SwiftGstBaseTransformInfo in_place_without_transform_ip_info = swift_gst_test_base_transform_info(
        "swiftoutofplace_c_mode_inplace_without_transform_ip",
        "SwiftGstTestOutOfPlaceCModeInPlaceWithoutTransformIP"
    );
    SwiftGstBaseTransformCallbacks in_place_without_transform_ip_callbacks =
        swift_gst_test_base_transform_callbacks();
    in_place_without_transform_ip_callbacks.transform_ip = NULL;
    result.in_place_without_transform_ip_registration_failed = !swift_gst_test_base_transform_register_info(
        &in_place_without_transform_ip_info,
        &in_place_without_transform_ip_callbacks,
        in_place_without_transform_ip_context
    );

    SwiftGstTestBaseTransformContext* out_without_transform_ip_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(out_without_transform_ip_context);
    SwiftGstBaseTransformInfo out_without_transform_ip_info =
        swift_gst_test_base_transform_out_of_place_info(
            "swiftoutofplace_c_mode_out_without_transform_ip",
            "SwiftGstTestOutOfPlaceCModeOutWithoutTransformIP"
        );
    SwiftGstBaseTransformCallbacks out_without_transform_ip_callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    out_without_transform_ip_callbacks.transform_ip = NULL;
    result.out_of_place_without_transform_ip_registration_succeeded =
        swift_gst_test_base_transform_register_info(
            &out_without_transform_ip_info,
            &out_without_transform_ip_callbacks,
            out_without_transform_ip_context
        );

    SwiftGstTestBaseTransformContext* out_without_transform_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(out_without_transform_context);
    SwiftGstBaseTransformInfo out_without_transform_info =
        swift_gst_test_base_transform_out_of_place_info(
            "swiftoutofplace_c_mode_out_without_transform",
            "SwiftGstTestOutOfPlaceCModeOutWithoutTransform"
        );
    SwiftGstBaseTransformCallbacks out_without_transform_callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    out_without_transform_callbacks.transform = NULL;
    result.out_of_place_without_transform_registration_failed =
        !swift_gst_test_base_transform_register_info(
            &out_without_transform_info,
            &out_without_transform_callbacks,
            out_without_transform_context
        );

    SwiftGstTestBaseTransformContext* missing_common_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(missing_common_context);
    SwiftGstBaseTransformInfo missing_common_info =
        swift_gst_test_base_transform_out_of_place_info(
            "swiftoutofplace_c_mode_missing_common",
            "SwiftGstTestOutOfPlaceCModeMissingCommon"
        );
    SwiftGstBaseTransformCallbacks missing_common_callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    missing_common_callbacks.start = NULL;
    result.missing_common_callback_registration_failed =
        !swift_gst_test_base_transform_register_info(
            &missing_common_info,
            &missing_common_callbacks,
            missing_common_context
        );

    return result;
}

static void swift_gst_test_base_transform_probe_class_vfuncs(
    const gchar* factory_name,
    gboolean* element_created,
    gpointer* transform_ip,
    gpointer* transform,
    gpointer* prepare_output_buffer
) {
    if (element_created != NULL) {
        *element_created = FALSE;
    }
    if (transform_ip != NULL) {
        *transform_ip = NULL;
    }
    if (transform != NULL) {
        *transform = NULL;
    }
    if (prepare_output_buffer != NULL) {
        *prepare_output_buffer = NULL;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (!element) {
        return;
    }
    if (element_created != NULL) {
        *element_created = TRUE;
    }

    GstBaseTransformClass* transform_class =
        GST_BASE_TRANSFORM_GET_CLASS(GST_BASE_TRANSFORM(element));
    if (transform_class != NULL) {
        if (transform_ip != NULL) {
            *transform_ip = (gpointer)transform_class->transform_ip;
        }
        if (transform != NULL) {
            *transform = (gpointer)transform_class->transform;
        }
        if (prepare_output_buffer != NULL) {
            *prepare_output_buffer = (gpointer)transform_class->prepare_output_buffer;
        }
    }

    gst_object_unref(element);
}

SwiftGstTestBaseTransformGeneralModeProbeResult swift_gst_test_base_transform_general_mode_probe(
    const gchar* in_place_factory_name,
    const gchar* in_place_type_name,
    const gchar* fixed_size_factory_name,
    const gchar* fixed_size_type_name,
    const gchar* general_factory_name,
    const gchar* general_type_name,
    const gchar* general_without_transform_factory_name,
    const gchar* general_without_transform_type_name
) {
    SwiftGstTestBaseTransformGeneralModeProbeResult result = {0};

    SwiftGstTestBaseTransformContext* in_place_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(in_place_context);
    SwiftGstBaseTransformInfo in_place_info = swift_gst_test_base_transform_info(
        in_place_factory_name,
        in_place_type_name
    );
    SwiftGstBaseTransformCallbacks in_place_callbacks =
        swift_gst_test_base_transform_callbacks();
    result.in_place_registration_succeeded = swift_gst_test_base_transform_register_info(
        &in_place_info,
        &in_place_callbacks,
        in_place_context
    );

    SwiftGstTestBaseTransformContext* fixed_size_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(fixed_size_context);
    SwiftGstBaseTransformInfo fixed_size_info =
        swift_gst_test_base_transform_out_of_place_info(
            fixed_size_factory_name,
            fixed_size_type_name
        );
    SwiftGstBaseTransformCallbacks fixed_size_callbacks =
        swift_gst_test_base_transform_out_of_place_callbacks();
    result.fixed_size_registration_succeeded = swift_gst_test_base_transform_register_info(
        &fixed_size_info,
        &fixed_size_callbacks,
        fixed_size_context
    );

    SwiftGstTestBaseTransformContext* general_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(general_context);
    SwiftGstBaseTransformInfo general_info =
        swift_gst_test_base_transform_general_out_of_place_info(
            general_factory_name,
            general_type_name
        );
    SwiftGstBaseTransformCallbacks general_callbacks =
        swift_gst_test_base_transform_general_out_of_place_callbacks();
    result.general_registration_succeeded = swift_gst_test_base_transform_register_info(
        &general_info,
        &general_callbacks,
        general_context
    );

    SwiftGstTestBaseTransformContext* general_without_transform_context =
        g_new0(SwiftGstTestBaseTransformContext, 1);
    swift_gst_test_base_transform_context_init(general_without_transform_context);
    SwiftGstBaseTransformInfo general_without_transform_info =
        swift_gst_test_base_transform_general_out_of_place_info(
            general_without_transform_factory_name,
            general_without_transform_type_name
        );
    SwiftGstBaseTransformCallbacks general_without_transform_callbacks =
        swift_gst_test_base_transform_general_out_of_place_callbacks();
    general_without_transform_callbacks.transform = NULL;
    result.general_without_transform_registration_failed =
        !swift_gst_test_base_transform_register_info(
            &general_without_transform_info,
            &general_without_transform_callbacks,
            general_without_transform_context
        );

    gpointer in_place_transform_ip = NULL;
    gpointer in_place_transform = NULL;
    gpointer in_place_prepare = NULL;
    gpointer fixed_size_transform_ip = NULL;
    gpointer fixed_size_transform = NULL;
    gpointer fixed_size_prepare = NULL;
    gpointer general_transform_ip = NULL;
    gpointer general_transform = NULL;
    gpointer general_prepare = NULL;

    if (result.in_place_registration_succeeded) {
        swift_gst_test_base_transform_probe_class_vfuncs(
            in_place_factory_name,
            &result.in_place_element_created,
            &in_place_transform_ip,
            &in_place_transform,
            &in_place_prepare
        );
    }
    if (result.fixed_size_registration_succeeded) {
        swift_gst_test_base_transform_probe_class_vfuncs(
            fixed_size_factory_name,
            &result.fixed_size_element_created,
            &fixed_size_transform_ip,
            &fixed_size_transform,
            &fixed_size_prepare
        );
    }
    if (result.general_registration_succeeded) {
        swift_gst_test_base_transform_probe_class_vfuncs(
            general_factory_name,
            &result.general_element_created,
            &general_transform_ip,
            &general_transform,
            &general_prepare
        );
    }

    result.in_place_installs_transform_ip = in_place_transform_ip != NULL;
    result.in_place_omits_transform = in_place_transform == NULL;
    result.in_place_omits_prepare_output_buffer =
        in_place_prepare == NULL || in_place_prepare != fixed_size_prepare;

    result.fixed_size_installs_transform = fixed_size_transform != NULL;
    result.fixed_size_omits_transform_ip = fixed_size_transform_ip == NULL;
    result.fixed_size_installs_prepare_output_buffer = fixed_size_prepare != NULL;

    result.general_installs_transform = general_transform != NULL;
    result.general_omits_transform_ip = general_transform_ip == NULL;
    result.general_omits_prepare_output_buffer =
        general_prepare == NULL || general_prepare != fixed_size_prepare;

    return result;
}

static GstQuery* swift_gst_test_base_transform_general_hook_probe_query(GstCaps* caps) {
    GstQuery* query = gst_query_new_allocation(caps, TRUE);
    if (query == NULL) {
        return NULL;
    }

    GstBufferPool* pool = gst_buffer_pool_new();
    gst_query_add_allocation_pool(query, pool, 32, 1, 2);
    if (pool != NULL) {
        gst_object_unref(pool);
    }

    GstAllocationParams params;
    gst_allocation_params_init(&params);
    params.align = 3;
    params.prefix = 1;
    params.padding = 2;
    GstAllocator* allocator = gst_allocator_find(NULL);
    gst_query_add_allocation_param(query, allocator, &params);
    if (allocator != NULL) {
        gst_object_unref(allocator);
    }

    gst_query_add_allocation_meta(query, gst_parent_buffer_meta_api_get_type(), NULL);
    return query;
}

static void swift_gst_test_base_transform_general_hook_probe_copy_decide_fields(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context,
    SwiftGstTestBaseTransformGeneralHookProbeResult* result
) {
    if (context == NULL || result == NULL) {
        return;
    }

    g_mutex_lock(&context->mutex);
    result->decide_query_caps_observed = context->query_caps_observed;
    result->decide_query_needs_pool_observed = context->query_needs_pool_observed;
    result->decide_pools_before = context->pools_before;
    result->decide_pools_after = context->pools_after;
    result->decide_params_before = context->params_before;
    result->decide_params_after = context->params_after;
    result->decide_metas_before = context->metas_before;
    result->decide_metas_after = context->metas_after;
    g_mutex_unlock(&context->mutex);
}

static void swift_gst_test_base_transform_general_hook_probe_copy_propose_fields(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context,
    SwiftGstTestBaseTransformGeneralHookProbeResult* result
) {
    if (context == NULL || result == NULL) {
        return;
    }

    g_mutex_lock(&context->mutex);
    result->propose_decide_query_caps_observed = context->propose_decide_query_caps_observed;
    result->propose_query_caps_observed = context->propose_query_caps_observed;
    g_mutex_unlock(&context->mutex);
}

static void swift_gst_test_base_transform_general_hook_probe_copy_filter_fields(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context,
    SwiftGstTestBaseTransformGeneralHookProbeResult* result
) {
    if (context == NULL || result == NULL) {
        return;
    }

    g_mutex_lock(&context->mutex);
    result->filter_api_observed = context->filter_api_observed;
    g_mutex_unlock(&context->mutex);
}

static void swift_gst_test_base_transform_general_hook_probe_copy_transform_meta_fields(
    SwiftGstTestBaseTransformGeneralHookProbeContext* context,
    SwiftGstTestBaseTransformGeneralHookProbeResult* result
) {
    if (context == NULL || result == NULL) {
        return;
    }

    g_mutex_lock(&context->mutex);
    result->transform_meta_api_observed = context->transform_meta_api_observed;
    g_mutex_unlock(&context->mutex);
}

SwiftGstTestBaseTransformGeneralHookProbeResult swift_gst_test_base_transform_general_hook_probe(
    const gchar* factory_name,
    const gchar* type_name
) {
    SwiftGstTestBaseTransformGeneralHookProbeResult result = {0};
    SwiftGstTestBaseTransformGeneralHookProbeContext* context =
        g_new0(SwiftGstTestBaseTransformGeneralHookProbeContext, 1);
    swift_gst_test_base_transform_general_hook_probe_context_init(context);

    SwiftGstBaseTransformInfo info =
        swift_gst_test_base_transform_general_out_of_place_info(factory_name, type_name);
    SwiftGstBaseTransformCallbacks callbacks =
        swift_gst_test_base_transform_general_hook_probe_callbacks();
    gchar* error_message = NULL;
    result.registration_succeeded = swift_gst_register_base_transform(
        &info,
        &callbacks,
        context,
        swift_gst_test_base_transform_general_hook_probe_retain,
        swift_gst_test_base_transform_general_hook_probe_release,
        &error_message
    );
    g_free(error_message);
    if (!result.registration_succeeded) {
        return result;
    }

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (element == NULL) {
        return result;
    }
    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);
    GstCaps* caps = gst_caps_from_string("video/x-raw,format=BGRA,width=2,height=2,framerate=30/1");
    if (transform_class == NULL || caps == NULL) {
        if (caps != NULL) {
            gst_caps_unref(caps);
        }
        gst_object_unref(element);
        return result;
    }

    if (transform_class->decide_allocation != NULL) {
        GstQuery* query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            TRUE
        );
        result.decide_value_true_returned_true =
            query != NULL && transform_class->decide_allocation(transform, query);
        swift_gst_test_base_transform_general_hook_probe_copy_decide_fields(context, &result);
        if (query != NULL) {
            gst_query_unref(query);
        }

        query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            FALSE
        );
        result.decide_value_false_returned_false =
            query != NULL && !transform_class->decide_allocation(transform, query);
        if (query != NULL) {
            gst_query_unref(query);
        }

        query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
            FALSE
        );
        result.decide_failure_returned_false =
            query != NULL && !transform_class->decide_allocation(transform, query);
        if (query != NULL) {
            gst_query_unref(query);
        }
    }

    if (transform_class->propose_allocation != NULL) {
        GstQuery* decide_query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        GstQuery* query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            TRUE
        );
        result.propose_value_true_returned_true =
            decide_query != NULL
            && query != NULL
            && transform_class->propose_allocation(transform, decide_query, query);
        swift_gst_test_base_transform_general_hook_probe_copy_propose_fields(context, &result);
        if (decide_query != NULL) {
            gst_query_unref(decide_query);
        }
        if (query != NULL) {
            gst_query_unref(query);
        }

        decide_query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            FALSE
        );
        result.propose_value_false_returned_false =
            decide_query != NULL
            && query != NULL
            && !transform_class->propose_allocation(transform, decide_query, query);
        if (decide_query != NULL) {
            gst_query_unref(decide_query);
        }
        if (query != NULL) {
            gst_query_unref(query);
        }

        decide_query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
            FALSE
        );
        result.propose_failure_returned_false =
            decide_query != NULL
            && query != NULL
            && !transform_class->propose_allocation(transform, decide_query, query);
        if (decide_query != NULL) {
            gst_query_unref(decide_query);
        }
        if (query != NULL) {
            gst_query_unref(query);
        }
    }

    if (transform_class->filter_meta != NULL) {
        GstQuery* query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            TRUE
        );
        result.filter_value_true_returned_true =
            query != NULL
            && transform_class->filter_meta(
                transform,
                query,
                gst_parent_buffer_meta_api_get_type(),
                NULL
            );
        swift_gst_test_base_transform_general_hook_probe_copy_filter_fields(context, &result);
        if (query != NULL) {
            gst_query_unref(query);
        }

        query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            FALSE
        );
        result.filter_value_false_returned_false =
            query != NULL
            && !transform_class->filter_meta(
                transform,
                query,
                gst_parent_buffer_meta_api_get_type(),
                NULL
            );
        if (query != NULL) {
            gst_query_unref(query);
        }

        query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
            FALSE
        );
        result.filter_failure_returned_false =
            query != NULL
            && !transform_class->filter_meta(
                transform,
                query,
                gst_parent_buffer_meta_api_get_type(),
                NULL
            );
        if (query != NULL) {
            gst_query_unref(query);
        }
    }

    GstBuffer* input = gst_buffer_new_allocate(NULL, 16, NULL);
    GstBuffer* output = gst_buffer_new_allocate(NULL, 16, NULL);
    if (transform_class->copy_metadata != NULL && input != NULL && output != NULL) {
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            FALSE
        );
        result.copy_value_false_returned_false =
            !transform_class->copy_metadata(transform, input, output);

        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
            FALSE
        );
        result.copy_failure_returned_false =
            !transform_class->copy_metadata(transform, input, output);
    }

    GstBuffer* parent = gst_buffer_new();
    GstParentBufferMeta* parent_meta =
        input != NULL && parent != NULL ? gst_buffer_add_parent_buffer_meta(input, parent) : NULL;
    if (transform_class->transform_meta != NULL && input != NULL && output != NULL && parent_meta != NULL) {
        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            FALSE
        );
        result.transform_meta_value_false_returned_false =
            !transform_class->transform_meta(transform, output, &parent_meta->parent, input);
        swift_gst_test_base_transform_general_hook_probe_copy_transform_meta_fields(context, &result);

        swift_gst_test_base_transform_general_hook_probe_set_result(
            context,
            SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
            FALSE
        );
        result.transform_meta_failure_returned_false =
            !transform_class->transform_meta(transform, output, &parent_meta->parent, input);
    }

    if (parent != NULL) {
        gst_buffer_unref(parent);
    }
    if (input != NULL) {
        gst_buffer_unref(input);
    }
    if (output != NULL) {
        gst_buffer_unref(output);
    }
    gst_caps_unref(caps);
    gst_object_unref(element);
    return result;
}

SwiftGstTestBaseTransformSwiftHookInvocationResult swift_gst_test_base_transform_invoke_general_hooks(
    const gchar* factory_name
) {
    SwiftGstTestBaseTransformSwiftHookInvocationResult result = {0};

    GstElement* element = gst_element_factory_make(factory_name, NULL);
    if (element == NULL) {
        return result;
    }
    result.element_created = TRUE;

    GstBaseTransform* transform = GST_BASE_TRANSFORM(element);
    GstBaseTransformClass* transform_class = GST_BASE_TRANSFORM_GET_CLASS(transform);
    GstCaps* caps = gst_caps_from_string("video/x-raw,format=BGRA,width=2,height=2,framerate=30/1");
    if (transform_class == NULL || caps == NULL) {
        if (caps != NULL) {
            gst_caps_unref(caps);
        }
        gst_object_unref(element);
        return result;
    }

    if (transform_class->decide_allocation != NULL) {
        GstQuery* query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        result.decide_allocation_returned_true =
            query != NULL && transform_class->decide_allocation(transform, query);
        if (query != NULL) {
            gst_query_unref(query);
        }
    }

    if (transform_class->propose_allocation != NULL) {
        GstQuery* decide_query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        GstQuery* query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        result.propose_allocation_returned_true =
            decide_query != NULL
            && query != NULL
            && transform_class->propose_allocation(transform, decide_query, query);
        if (decide_query != NULL) {
            gst_query_unref(decide_query);
        }
        if (query != NULL) {
            gst_query_unref(query);
        }
    }

    if (transform_class->filter_meta != NULL) {
        GstQuery* query = swift_gst_test_base_transform_general_hook_probe_query(caps);
        result.filter_meta_returned_true =
            query != NULL
            && transform_class->filter_meta(
                transform,
                query,
                gst_parent_buffer_meta_api_get_type(),
                NULL
            );
        if (query != NULL) {
            gst_query_unref(query);
        }
    }

    GstBuffer* input = gst_buffer_new_allocate(NULL, 16, NULL);
    GstBuffer* output = gst_buffer_new_allocate(NULL, 16, NULL);
    GstBuffer* parent = gst_buffer_new();
    GstParentBufferMeta* parent_meta =
        input != NULL && parent != NULL ? gst_buffer_add_parent_buffer_meta(input, parent) : NULL;
    if (transform_class->transform_meta != NULL && input != NULL && output != NULL && parent_meta != NULL) {
        result.transform_meta_returned_true =
            transform_class->transform_meta(transform, output, &parent_meta->parent, input);
    }

    if (parent != NULL) {
        gst_buffer_unref(parent);
    }
    if (input != NULL) {
        gst_buffer_unref(input);
    }
    if (output != NULL) {
        gst_buffer_unref(output);
    }
    gst_caps_unref(caps);
    gst_object_unref(element);
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
