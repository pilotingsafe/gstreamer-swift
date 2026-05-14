#ifndef CGSTREAMER_TEST_SUPPORT_H
#define CGSTREAMER_TEST_SUPPORT_H

#include <gst/gst.h>
#include <gst/app/gstappsink.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SwiftGstTestProbe SwiftGstTestProbe;

typedef enum {
    SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_OK,
    SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_CREATE_APPSINK_FAILED,
    SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_CONNECT_FAILED,
    SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_EMIT_THREAD_FAILED,
    SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_TIMEOUT,
    SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_UNBALANCED_RETAIN_RELEASE,
} SwiftGstTestCallbackRegistrationRaceStatus;

typedef struct {
    gboolean success;
    SwiftGstTestCallbackRegistrationRaceStatus status;
    guint callback_count;
    guint retain_count;
    guint release_count;
} SwiftGstTestCallbackRegistrationRaceResult;

typedef struct {
    guint retain_count;
    guint release_count;
    guint create_count;
    guint destroy_count;
    guint start_count;
    guint stop_count;
    guint set_caps_count;
    guint render_count;
} SwiftGstTestBaseSinkCallbackCounts;

typedef struct {
    gboolean success_registration_succeeded;
    gboolean duplicate_factory_registration_failed;
    gboolean duplicate_type_registration_failed;
    SwiftGstTestBaseSinkCallbackCounts success_context;
    SwiftGstTestBaseSinkCallbackCounts duplicate_factory_context;
    SwiftGstTestBaseSinkCallbackCounts duplicate_type_context;
} SwiftGstTestBaseSinkOwnershipProbeResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean start_returned_false;
    gboolean render_returned_flow_error;
    gboolean stop_returned_true;
    SwiftGstTestBaseSinkCallbackCounts callback_counts;
} SwiftGstTestBaseSinkMissingInstanceProbeResult;

gboolean swift_gst_test_element_factory_exists(const gchar* factory_name);
GLogLevelFlags swift_gst_test_enable_fatal_criticals(void);
void swift_gst_test_restore_fatal_mask(GLogLevelFlags previous);

SwiftGstTestProbe* swift_gst_test_install_bus_error_after_buffers(
    GstElement* pipeline,
    const gchar* element_name,
    const gchar* pad_name,
    guint after_buffers,
    const gchar* message,
    const gchar* debug
);

SwiftGstTestProbe* swift_gst_test_install_marker_after_buffers(
    GstElement* pipeline,
    const gchar* element_name,
    const gchar* pad_name,
    guint after_buffers,
    const gchar* marker
);

guint swift_gst_test_probe_buffer_count(SwiftGstTestProbe* probe);
gboolean swift_gst_test_probe_acknowledged(SwiftGstTestProbe* probe);
void swift_gst_test_probe_free(SwiftGstTestProbe* probe);

gboolean swift_gst_test_post_bus_error(
    GstElement* pipeline,
    const gchar* message,
    const gchar* debug
);

gboolean swift_gst_test_post_element_marker(
    GstElement* pipeline,
    const gchar* marker
);

gboolean swift_gst_test_signal_handler_is_connected(GObject* object, gulong handler_id);
guint swift_gst_test_signal_handler_count(GObject* object, const gchar* signal_name);

guint swift_gst_test_buffer_refcount(GstBuffer* buffer);
gchar* swift_gst_test_sample_caps_string(GstSample* sample);
gchar* swift_gst_test_appsink_first_sample_caps_string(GstAppSink* appsink, GstClockTime timeout);

gboolean swift_gst_test_bus_pop_marker(GstBus* bus, const gchar* marker, GstClockTime timeout);

SwiftGstTestCallbackRegistrationRaceResult swift_gst_test_callback_registration_disconnect_while_in_flight(void);

SwiftGstTestBaseSinkOwnershipProbeResult swift_gst_test_base_sink_class_context_ownership_probe(
    const gchar* success_factory_name,
    const gchar* success_type_name,
    const gchar* duplicate_factory_type_name,
    const gchar* duplicate_type_factory_name
);

SwiftGstTestBaseSinkMissingInstanceProbeResult swift_gst_test_base_sink_missing_instance_probe(
    const gchar* factory_name,
    const gchar* type_name
);

#ifdef __cplusplus
}
#endif

#endif /* CGSTREAMER_TEST_SUPPORT_H */
