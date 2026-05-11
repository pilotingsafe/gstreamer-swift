#include "include/CGStreamerTestSupport.h"

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

GLogLevelFlags swift_gst_test_enable_fatal_criticals(void) {
    GLogLevelFlags previous = g_log_set_always_fatal(G_LOG_FATAL_MASK);
    g_log_set_always_fatal(previous | G_LOG_LEVEL_CRITICAL);
    return previous;
}

void swift_gst_test_restore_fatal_mask(GLogLevelFlags previous) {
    g_log_set_always_fatal(previous);
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
