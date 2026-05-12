#ifndef CGSTREAMER_TEST_SUPPORT_H
#define CGSTREAMER_TEST_SUPPORT_H

#include <gst/gst.h>
#include <gst/app/gstappsink.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SwiftGstTestProbe SwiftGstTestProbe;

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

#ifdef __cplusplus
}
#endif

#endif /* CGSTREAMER_TEST_SUPPORT_H */
