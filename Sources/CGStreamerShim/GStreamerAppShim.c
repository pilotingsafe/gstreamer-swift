#include "include/GStreamerAppShim.h"

typedef enum {
    SWIFT_GST_CALLBACK_APP_SINK_NEW_SAMPLE,
    SWIFT_GST_CALLBACK_APP_SINK_EOS,
    SWIFT_GST_CALLBACK_BUS_SYNC_MESSAGE
} SwiftGstCallbackKind;

struct SwiftGstCallbackRegistration {
    GObject* instance;
    gulong handler_id;
    SwiftGstCallbackKind kind;
    union {
        SwiftGstAppSinkEventCallback app_sink_event;
        SwiftGstBusSyncMessageCallback bus_sync_message;
    } callback;
    void* context;
    SwiftGstContextRetainFunc retain_context;
    SwiftGstContextReleaseFunc release_context;
    GMutex mutex;
    guint in_flight;
    gboolean disconnected;
    gboolean signal_destroyed;
    gboolean destroying;
};

static void swift_gst_callback_registration_retain_context(SwiftGstCallbackRegistration* registration) {
    if (registration->context != NULL && registration->retain_context != NULL) {
        registration->retain_context(registration->context);
    }
}

static void swift_gst_callback_registration_release_context(SwiftGstCallbackRegistration* registration) {
    if (registration->context != NULL && registration->release_context != NULL) {
        registration->release_context(registration->context);
    }
}

/* Caller must hold registration->mutex. */
static gboolean swift_gst_callback_registration_claim_destroy_locked(
    SwiftGstCallbackRegistration* registration
) {
    if (registration->signal_destroyed
        && registration->in_flight == 0
        && !registration->destroying) {
        registration->destroying = TRUE;
        return TRUE;
    }

    return FALSE;
}

static void swift_gst_callback_registration_destroy_claimed(
    SwiftGstCallbackRegistration* registration
) {
    swift_gst_callback_registration_release_context(registration);
    if (registration->kind == SWIFT_GST_CALLBACK_BUS_SYNC_MESSAGE) {
        gst_bus_disable_sync_message_emission(GST_BUS(registration->instance));
    }
    g_object_unref(registration->instance);
    g_mutex_clear(&registration->mutex);
    g_free(registration);
}

static SwiftGstCallbackRegistration* swift_gst_callback_registration_new(
    GObject* instance,
    SwiftGstCallbackKind kind,
    void* context,
    SwiftGstContextRetainFunc retain_context,
    SwiftGstContextReleaseFunc release_context
) {
    if (instance == NULL) {
        return NULL;
    }

    SwiftGstCallbackRegistration* registration = g_new0(SwiftGstCallbackRegistration, 1);
    registration->instance = g_object_ref(instance);
    registration->kind = kind;
    registration->context = context;
    registration->retain_context = retain_context;
    registration->release_context = release_context;
    g_mutex_init(&registration->mutex);
    swift_gst_callback_registration_retain_context(registration);
    return registration;
}

static gboolean swift_gst_callback_registration_begin(
    SwiftGstCallbackRegistration* registration,
    void** context
) {
    gboolean should_call = FALSE;

    g_mutex_lock(&registration->mutex);
    if (!registration->disconnected && !registration->signal_destroyed) {
        registration->in_flight++;
        *context = registration->context;
        should_call = TRUE;
    }
    g_mutex_unlock(&registration->mutex);

    if (should_call) {
        swift_gst_callback_registration_retain_context(registration);
    }

    return should_call;
}

static void swift_gst_callback_registration_end(SwiftGstCallbackRegistration* registration) {
    gboolean destroy_claimed = FALSE;

    swift_gst_callback_registration_release_context(registration);

    g_mutex_lock(&registration->mutex);
    if (registration->in_flight > 0) {
        registration->in_flight--;
    }
    destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
    g_mutex_unlock(&registration->mutex);

    if (destroy_claimed) {
        swift_gst_callback_registration_destroy_claimed(registration);
    }
}

static void swift_gst_callback_registration_signal_destroy(gpointer data, GClosure* closure) {
    (void)closure;

    SwiftGstCallbackRegistration* registration = (SwiftGstCallbackRegistration*)data;
    if (registration == NULL) {
        return;
    }

    gboolean destroy_claimed = FALSE;

    g_mutex_lock(&registration->mutex);
    registration->disconnected = TRUE;
    registration->signal_destroyed = TRUE;
    registration->handler_id = 0;
    destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
    g_mutex_unlock(&registration->mutex);

    if (destroy_claimed) {
        swift_gst_callback_registration_destroy_claimed(registration);
    }
}

static GstFlowReturn swift_gst_app_sink_new_sample_trampoline(
    GstAppSink* appsink,
    gpointer data
) {
    (void)appsink;

    SwiftGstCallbackRegistration* registration = (SwiftGstCallbackRegistration*)data;
    void* context = NULL;
    if (!swift_gst_callback_registration_begin(registration, &context)) {
        return GST_FLOW_OK;
    }

    SwiftGstAppSinkEventCallback callback = registration->callback.app_sink_event;
    if (callback != NULL) {
        callback(context);
    }

    swift_gst_callback_registration_end(registration);
    return GST_FLOW_OK;
}

static void swift_gst_app_sink_eos_trampoline(GstAppSink* appsink, gpointer data) {
    (void)appsink;

    SwiftGstCallbackRegistration* registration = (SwiftGstCallbackRegistration*)data;
    void* context = NULL;
    if (!swift_gst_callback_registration_begin(registration, &context)) {
        return;
    }

    SwiftGstAppSinkEventCallback callback = registration->callback.app_sink_event;
    if (callback != NULL) {
        callback(context);
    }

    swift_gst_callback_registration_end(registration);
}

static void swift_gst_bus_sync_message_trampoline(
    GstBus* bus,
    GstMessage* message,
    gpointer data
) {
    (void)bus;

    SwiftGstCallbackRegistration* registration = (SwiftGstCallbackRegistration*)data;
    void* context = NULL;
    if (!swift_gst_callback_registration_begin(registration, &context)) {
        return;
    }

    SwiftGstBusSyncMessageCallback callback = registration->callback.bus_sync_message;
    if (callback != NULL) {
        callback(message, context);
    }

    swift_gst_callback_registration_end(registration);
}

// MARK: - AppSink

GstSample* swift_gst_app_sink_pull_sample(GstAppSink* appsink) {
    return gst_app_sink_pull_sample(appsink);
}

GstSample* swift_gst_app_sink_try_pull_sample(GstAppSink* appsink, GstClockTime timeout) {
    return gst_app_sink_try_pull_sample(appsink, timeout);
}

gboolean swift_gst_app_sink_is_eos(GstAppSink* appsink) {
    return gst_app_sink_is_eos(appsink);
}

void swift_gst_app_sink_set_caps(GstAppSink* appsink, GstCaps* caps) {
    gst_app_sink_set_caps(appsink, caps);
}

GstCaps* swift_gst_app_sink_get_caps(GstAppSink* appsink) {
    return gst_app_sink_get_caps(appsink);
}

void swift_gst_app_sink_set_emit_signals(GstAppSink* appsink, gboolean emit) {
    g_object_set(G_OBJECT(appsink), "emit-signals", emit, NULL);
}

void swift_gst_app_sink_set_max_buffers(GstAppSink* appsink, guint max) {
    g_object_set(G_OBJECT(appsink), "max-buffers", max, NULL);
}

void swift_gst_app_sink_set_drop(GstAppSink* appsink, gboolean drop) {
    g_object_set(G_OBJECT(appsink), "drop", drop, NULL);
}

SwiftGstCallbackRegistration* swift_gst_app_sink_connect_new_sample(
    GstAppSink* appsink,
    SwiftGstAppSinkEventCallback callback,
    void* context,
    SwiftGstContextRetainFunc retain_context,
    SwiftGstContextReleaseFunc release_context
) {
    if (appsink == NULL || callback == NULL) {
        return NULL;
    }

    SwiftGstCallbackRegistration* registration = swift_gst_callback_registration_new(
        G_OBJECT(appsink),
        SWIFT_GST_CALLBACK_APP_SINK_NEW_SAMPLE,
        context,
        retain_context,
        release_context
    );
    if (registration == NULL) {
        return NULL;
    }

    registration->callback.app_sink_event = callback;
    registration->handler_id = g_signal_connect_data(
        G_OBJECT(appsink),
        "new-sample",
        G_CALLBACK(swift_gst_app_sink_new_sample_trampoline),
        registration,
        swift_gst_callback_registration_signal_destroy,
        0
    );
    if (registration->handler_id == 0) {
        gboolean destroy_claimed = FALSE;

        g_mutex_lock(&registration->mutex);
        registration->disconnected = TRUE;
        registration->signal_destroyed = TRUE;
        destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
        g_mutex_unlock(&registration->mutex);
        if (destroy_claimed) {
            swift_gst_callback_registration_destroy_claimed(registration);
        }
        return NULL;
    }
    return registration;
}

SwiftGstCallbackRegistration* swift_gst_app_sink_connect_eos(
    GstAppSink* appsink,
    SwiftGstAppSinkEventCallback callback,
    void* context,
    SwiftGstContextRetainFunc retain_context,
    SwiftGstContextReleaseFunc release_context
) {
    if (appsink == NULL || callback == NULL) {
        return NULL;
    }

    SwiftGstCallbackRegistration* registration = swift_gst_callback_registration_new(
        G_OBJECT(appsink),
        SWIFT_GST_CALLBACK_APP_SINK_EOS,
        context,
        retain_context,
        release_context
    );
    if (registration == NULL) {
        return NULL;
    }

    registration->callback.app_sink_event = callback;
    registration->handler_id = g_signal_connect_data(
        G_OBJECT(appsink),
        "eos",
        G_CALLBACK(swift_gst_app_sink_eos_trampoline),
        registration,
        swift_gst_callback_registration_signal_destroy,
        0
    );
    if (registration->handler_id == 0) {
        gboolean destroy_claimed = FALSE;

        g_mutex_lock(&registration->mutex);
        registration->disconnected = TRUE;
        registration->signal_destroyed = TRUE;
        destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
        g_mutex_unlock(&registration->mutex);
        if (destroy_claimed) {
            swift_gst_callback_registration_destroy_claimed(registration);
        }
        return NULL;
    }
    return registration;
}

SwiftGstCallbackRegistration* swift_gst_bus_connect_sync_message_observer(
    GstBus* bus,
    SwiftGstBusSyncMessageCallback callback,
    void* context,
    SwiftGstContextRetainFunc retain_context,
    SwiftGstContextReleaseFunc release_context
) {
    if (bus == NULL || callback == NULL) {
        return NULL;
    }

    SwiftGstCallbackRegistration* registration = swift_gst_callback_registration_new(
        G_OBJECT(bus),
        SWIFT_GST_CALLBACK_BUS_SYNC_MESSAGE,
        context,
        retain_context,
        release_context
    );
    if (registration == NULL) {
        return NULL;
    }

    registration->callback.bus_sync_message = callback;
    gst_bus_enable_sync_message_emission(bus);
    registration->handler_id = g_signal_connect_data(
        G_OBJECT(bus),
        "sync-message",
        G_CALLBACK(swift_gst_bus_sync_message_trampoline),
        registration,
        swift_gst_callback_registration_signal_destroy,
        0
    );
    if (registration->handler_id == 0) {
        gboolean destroy_claimed = FALSE;

        g_mutex_lock(&registration->mutex);
        registration->disconnected = TRUE;
        registration->signal_destroyed = TRUE;
        destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
        g_mutex_unlock(&registration->mutex);
        if (destroy_claimed) {
            swift_gst_callback_registration_destroy_claimed(registration);
        }
        return NULL;
    }
    return registration;
}

void swift_gst_callback_registration_disconnect(SwiftGstCallbackRegistration* registration) {
    if (registration == NULL) {
        return;
    }

    gboolean destroy_claimed = FALSE;
    gulong handler_id = 0;
    GObject* instance = NULL;

    g_mutex_lock(&registration->mutex);
    if (!registration->disconnected) {
        registration->disconnected = TRUE;
        handler_id = registration->handler_id;
        if (handler_id != 0) {
            instance = registration->instance;
        } else {
            registration->signal_destroyed = TRUE;
            destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
        }
    } else {
        destroy_claimed = swift_gst_callback_registration_claim_destroy_locked(registration);
    }
    g_mutex_unlock(&registration->mutex);

    if (handler_id != 0 && instance != NULL) {
        g_signal_handler_disconnect(instance, handler_id);
    } else if (destroy_claimed) {
        swift_gst_callback_registration_destroy_claimed(registration);
    }
}

// MARK: - AppSrc

GstFlowReturn swift_gst_app_src_push_buffer(GstAppSrc* appsrc, GstBuffer* buffer) {
    return gst_app_src_push_buffer(appsrc, buffer);
}

GstFlowReturn swift_gst_app_src_end_of_stream(GstAppSrc* appsrc) {
    return gst_app_src_end_of_stream(appsrc);
}

void swift_gst_app_src_set_caps(GstAppSrc* appsrc, GstCaps* caps) {
    gst_app_src_set_caps(appsrc, caps);
}

void swift_gst_app_src_set_stream_type(GstAppSrc* appsrc, GstAppStreamType type) {
    g_object_set(G_OBJECT(appsrc), "stream-type", type, NULL);
}

void swift_gst_app_src_set_size(GstAppSrc* appsrc, gint64 size) {
    gst_app_src_set_size(appsrc, size);
}

// MARK: - Sample/Buffer utilities

GstBuffer* swift_gst_sample_get_buffer(void* sample) {
    return gst_sample_get_buffer((GstSample*)sample);
}

GstCaps* swift_gst_sample_get_caps(void* sample) {
    return gst_sample_get_caps((GstSample*)sample);
}

void swift_gst_sample_unref(void* sample) {
    gst_sample_unref((GstSample*)sample);
}

gsize swift_gst_buffer_get_size(GstBuffer* buffer) {
    return gst_buffer_get_size(buffer);
}

GstBufferFlags swift_gst_buffer_get_flags(GstBuffer* buffer) {
    return GST_BUFFER_FLAGS(buffer);
}

void swift_gst_buffer_set_flags(GstBuffer* buffer, GstBufferFlags flags) {
    GST_BUFFER_FLAGS(buffer) = flags;
}

gboolean swift_gst_buffer_has_gap_flag(GstBuffer* buffer) {
    return GST_BUFFER_FLAG_IS_SET(buffer, GST_BUFFER_FLAG_GAP);
}

gboolean swift_gst_buffer_has_discont_flag(GstBuffer* buffer) {
    return GST_BUFFER_FLAG_IS_SET(buffer, GST_BUFFER_FLAG_DISCONT);
}

GstBufferFlags swift_gst_buffer_flag_gap(void) {
    return GST_BUFFER_FLAG_GAP;
}

GstBufferFlags swift_gst_buffer_flag_discont(void) {
    return GST_BUFFER_FLAG_DISCONT;
}

GstBuffer* swift_gst_buffer_ref(GstBuffer* buffer) {
    return gst_buffer_ref(buffer);
}

void swift_gst_buffer_unref(GstBuffer* buffer) {
    gst_buffer_unref(buffer);
}

gboolean swift_gst_buffer_map_read(GstBuffer* buffer, GstMapInfo* info) {
    return gst_buffer_map(buffer, info, GST_MAP_READ);
}

gboolean swift_gst_buffer_map_write(GstBuffer* buffer, GstMapInfo* info) {
    return gst_buffer_map(buffer, info, GST_MAP_WRITE);
}

void swift_gst_buffer_unmap(GstBuffer* buffer, GstMapInfo* info) {
    gst_buffer_unmap(buffer, info);
}

GstBuffer* swift_gst_buffer_new_allocate(gsize size) {
    return gst_buffer_new_allocate(NULL, size, NULL);
}

gsize swift_gst_buffer_fill(GstBuffer* buffer, gsize offset, gconstpointer src, gsize size) {
    return gst_buffer_fill(buffer, offset, src, size);
}

// MARK: - Buffer Timestamps

GstClockTime swift_gst_buffer_get_pts(GstBuffer* buffer) {
    return GST_BUFFER_PTS(buffer);
}

GstClockTime swift_gst_buffer_get_dts(GstBuffer* buffer) {
    return GST_BUFFER_DTS(buffer);
}

GstClockTime swift_gst_buffer_get_duration(GstBuffer* buffer) {
    return GST_BUFFER_DURATION(buffer);
}

void swift_gst_buffer_set_pts(GstBuffer* buffer, GstClockTime pts) {
    GST_BUFFER_PTS(buffer) = pts;
}

void swift_gst_buffer_set_dts(GstBuffer* buffer, GstClockTime dts) {
    GST_BUFFER_DTS(buffer) = dts;
}

void swift_gst_buffer_set_duration(GstBuffer* buffer, GstClockTime duration) {
    GST_BUFFER_DURATION(buffer) = duration;
}

gboolean swift_gst_clock_time_is_valid(GstClockTime time) {
    return GST_CLOCK_TIME_IS_VALID(time);
}

GstClockTime swift_gst_clock_time_none(void) {
    return GST_CLOCK_TIME_NONE;
}

GstClockTime swift_gst_second(void) {
    return GST_SECOND;
}

// MARK: - AppSrc additional functions

void swift_gst_app_src_set_format(GstAppSrc* appsrc, GstFormat format) {
    g_object_set(G_OBJECT(appsrc), "format", format, NULL);
}

void swift_gst_app_src_set_is_live(GstAppSrc* appsrc, gboolean is_live) {
    g_object_set(G_OBJECT(appsrc), "is-live", is_live, NULL);
}

void swift_gst_app_src_set_max_bytes(GstAppSrc* appsrc, guint64 max) {
    g_object_set(G_OBJECT(appsrc), "max-bytes", max, NULL);
}

void swift_gst_app_src_set_latency(GstAppSrc* appsrc, guint64 min, guint64 max) {
    g_object_set(G_OBJECT(appsrc), "min-latency", (gint64)min, "max-latency", (gint64)max, NULL);
}

GstBuffer* swift_gst_buffer_new_wrapped_full(gconstpointer data, gsize size, GstClockTime pts, GstClockTime duration) {
    if (data == NULL && size > 0) {
        return NULL;
    }

    GstBuffer* buffer = gst_buffer_new_allocate(NULL, size, NULL);
    if (buffer == NULL) {
        return NULL;
    }

    if (size > 0) {
        gst_buffer_fill(buffer, 0, data, size);
    }

    GST_BUFFER_PTS(buffer) = pts;
    GST_BUFFER_DURATION(buffer) = duration;
    return buffer;
}
