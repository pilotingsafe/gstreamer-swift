#ifndef CGSTREAMER_TEST_SUPPORT_H
#define CGSTREAMER_TEST_SUPPORT_H

#include <gst/gst.h>
#include <gst/app/gstappsink.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SwiftGstTestExpectedCriticals SwiftGstTestExpectedCriticals;
typedef struct SwiftGstTestProbe SwiftGstTestProbe;

typedef gboolean (*SwiftGstTestDynamicPluginInitCallback)(GstPlugin* plugin, gpointer user_data);

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

typedef struct {
    guint retain_count;
    guint release_count;
    guint create_count;
    guint destroy_count;
    guint start_count;
    guint stop_count;
    guint set_caps_count;
    guint transform_ip_count;
} SwiftGstTestBaseTransformCallbackCounts;

typedef struct {
    gboolean success_registration_succeeded;
    gboolean duplicate_factory_registration_failed;
    gboolean duplicate_type_registration_failed;
    SwiftGstTestBaseTransformCallbackCounts success_context;
    SwiftGstTestBaseTransformCallbackCounts duplicate_factory_context;
    SwiftGstTestBaseTransformCallbackCounts duplicate_type_context;
} SwiftGstTestBaseTransformOwnershipProbeResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean nil_buffer_returned_flow_error;
    gboolean non_writable_buffer_returned_flow_error;
    gboolean non_writable_buffer_was_not_writable;
    gboolean non_writable_buffer_returned_ok;
    guint nil_buffer_callback_count;
    guint non_writable_buffer_callback_count;
    SwiftGstTestBaseTransformCallbackCounts callback_counts;
} SwiftGstTestBaseTransformBufferRejectionProbeResult;

typedef struct {
    gboolean element_created;
    gboolean transform_ip_on_passthrough;
    gboolean non_writable_buffer_was_not_writable;
    gboolean transform_ip_returned_ok;
    gboolean transform_ip_returned_flow_error;
} SwiftGstTestBaseTransformNonWritableInvocationResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean start_returned_false;
    gboolean set_caps_returned_false;
    gboolean transform_ip_returned_flow_error;
    gboolean stop_returned_true;
    SwiftGstTestBaseTransformCallbackCounts callback_counts;
} SwiftGstTestBaseTransformMissingInstanceProbeResult;

typedef struct {
    guint retain_count;
    guint release_count;
    guint create_count;
    guint destroy_count;
    guint start_count;
    guint stop_count;
    guint set_caps_count;
    guint transform_count;
} SwiftGstTestBaseTransformOutOfPlaceCallbackCounts;

typedef struct {
    gboolean success_registration_succeeded;
    gboolean duplicate_factory_registration_failed;
    gboolean duplicate_type_registration_failed;
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts success_context;
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts duplicate_factory_context;
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts duplicate_type_context;
} SwiftGstTestBaseTransformOutOfPlaceOwnershipProbeResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean start_returned_false;
    gboolean set_caps_returned_false;
    gboolean transform_returned_flow_error;
    gboolean stop_returned_true;
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts callback_counts;
} SwiftGstTestBaseTransformOutOfPlaceMissingInstanceProbeResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean prepare_output_returned_ok;
    gboolean transform_returned_ok;
    gboolean output_is_distinct_from_input;
    gboolean output_is_writable;
    gboolean pts_preserved;
    gboolean duration_preserved;
    gsize input_size;
    gsize output_size;
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts callback_counts;
} SwiftGstTestBaseTransformOutOfPlaceOutputAllocationProbeResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean prepare_output_returned_flow_error;
    gboolean transform_not_called;
    SwiftGstTestBaseTransformOutOfPlaceCallbackCounts callback_counts;
} SwiftGstTestBaseTransformOutOfPlaceAllocationFailureProbeResult;

typedef struct {
    gboolean unknown_mode_registration_failed;
    gboolean in_place_without_transform_registration_succeeded;
    gboolean in_place_without_transform_ip_registration_failed;
    gboolean out_of_place_without_transform_ip_registration_succeeded;
    gboolean out_of_place_without_transform_registration_failed;
    gboolean missing_common_callback_registration_failed;
} SwiftGstTestBaseTransformModeValidationProbeResult;

typedef struct {
    gboolean in_place_registration_succeeded;
    gboolean fixed_size_registration_succeeded;
    gboolean general_registration_succeeded;
    gboolean in_place_element_created;
    gboolean fixed_size_element_created;
    gboolean general_element_created;
    gboolean in_place_installs_transform_ip;
    gboolean in_place_omits_transform;
    gboolean in_place_omits_prepare_output_buffer;
    gboolean fixed_size_installs_transform;
    gboolean fixed_size_omits_transform_ip;
    gboolean fixed_size_installs_prepare_output_buffer;
    gboolean general_installs_transform;
    gboolean general_omits_transform_ip;
    gboolean general_omits_prepare_output_buffer;
    gboolean general_without_transform_registration_failed;
} SwiftGstTestBaseTransformGeneralModeProbeResult;

typedef struct {
    gboolean registration_succeeded;
    gboolean element_created;
    gboolean decide_value_true_returned_true;
    gboolean decide_value_false_returned_false;
    gboolean decide_failure_returned_false;
    gboolean decide_query_caps_observed;
    gboolean decide_query_needs_pool_observed;
    guint decide_pools_before;
    guint decide_pools_after;
    guint decide_params_before;
    guint decide_params_after;
    guint decide_metas_before;
    guint decide_metas_after;
    gboolean propose_value_true_returned_true;
    gboolean propose_value_false_returned_false;
    gboolean propose_failure_returned_false;
    gboolean propose_decide_query_caps_observed;
    gboolean propose_query_caps_observed;
    gboolean filter_value_true_returned_true;
    gboolean filter_value_false_returned_false;
    gboolean filter_failure_returned_false;
    gboolean filter_api_observed;
    gboolean copy_value_false_returned_false;
    gboolean copy_failure_returned_false;
    gboolean transform_meta_value_false_returned_false;
    gboolean transform_meta_failure_returned_false;
    gboolean transform_meta_api_observed;
} SwiftGstTestBaseTransformGeneralHookProbeResult;

typedef struct {
    gboolean element_created;
    gboolean decide_allocation_returned_true;
    gboolean propose_allocation_returned_true;
    gboolean filter_meta_returned_true;
    gboolean transform_meta_returned_true;
} SwiftGstTestBaseTransformSwiftHookInvocationResult;

typedef struct {
    gboolean success;
    gboolean bool_value;
    gint int_value;
    gdouble double_value;
    gchar* string_value;
    gchar* enum_value;
} SwiftGstTestNativePropertyDefaultsProbeResult;

gboolean swift_gst_test_element_factory_exists(const gchar* factory_name);
guint swift_gst_test_element_factory_rank(const gchar* factory_name);
gboolean swift_gst_test_element_factory_has_plugin_owner(const gchar* factory_name);
gboolean swift_gst_test_element_factory_plugin_name_matches(
    const gchar* factory_name,
    const gchar* plugin_name
);
GLogLevelFlags swift_gst_test_enable_fatal_criticals(void);
void swift_gst_test_restore_fatal_mask(GLogLevelFlags previous);
void swift_gst_test_lock_glib_log_state(void);
void swift_gst_test_unlock_glib_log_state(void);
SwiftGstTestExpectedCriticals* swift_gst_test_expect_gobject_criticals_begin(
    const gchar* first_fragment,
    const gchar* second_fragment
);
gboolean swift_gst_test_expect_gobject_criticals_end(SwiftGstTestExpectedCriticals* expectation);
void swift_gst_test_emit_gobject_critical(const gchar* message);
GParamFlags swift_gst_test_param_mutable_playing(void);
guint swift_gst_test_element_property_id(GstElement* element, const gchar* property_name);

gboolean swift_gst_test_native_property_invoke_numeric_set_property_callbacks(
    GstElement* element,
    const gchar* int_name,
    gint int_value,
    const gchar* double_name,
    gdouble double_value
);

gboolean swift_gst_test_register_static_plugin_with_init_callback(
    const gchar* name,
    SwiftGstTestDynamicPluginInitCallback callback,
    gpointer user_data
);

SwiftGstTestNativePropertyDefaultsProbeResult swift_gst_test_native_property_missing_instance_defaults_probe(
    GstElement* element,
    gboolean is_base_transform,
    const gchar* bool_name,
    const gchar* int_name,
    const gchar* double_name,
    const gchar* string_name,
    const gchar* enum_name
);

void swift_gst_test_native_property_defaults_probe_result_clear(
    SwiftGstTestNativePropertyDefaultsProbeResult* result
);

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

SwiftGstTestBaseTransformOwnershipProbeResult swift_gst_test_base_transform_class_context_ownership_probe(
    const gchar* success_factory_name,
    const gchar* success_type_name,
    const gchar* duplicate_factory_type_name,
    const gchar* duplicate_type_factory_name
);

SwiftGstTestBaseTransformBufferRejectionProbeResult swift_gst_test_base_transform_buffer_rejection_probe(
    const gchar* factory_name,
    const gchar* type_name
);

SwiftGstTestBaseTransformNonWritableInvocationResult
swift_gst_test_base_transform_invoke_non_writable_transform_ip(
    const gchar* factory_name,
    const guint8* data,
    gsize size
);

SwiftGstTestBaseTransformMissingInstanceProbeResult swift_gst_test_base_transform_missing_instance_probe(
    const gchar* factory_name,
    const gchar* type_name
);

SwiftGstTestBaseTransformOutOfPlaceOwnershipProbeResult swift_gst_test_base_transform_out_of_place_class_context_ownership_probe(
    const gchar* success_factory_name,
    const gchar* success_type_name,
    const gchar* duplicate_factory_type_name,
    const gchar* duplicate_type_factory_name
);

SwiftGstTestBaseTransformOutOfPlaceMissingInstanceProbeResult swift_gst_test_base_transform_out_of_place_missing_instance_probe(
    const gchar* factory_name,
    const gchar* type_name
);

SwiftGstTestBaseTransformOutOfPlaceOutputAllocationProbeResult swift_gst_test_base_transform_out_of_place_output_allocation_probe(
    const gchar* factory_name,
    const gchar* type_name
);

SwiftGstTestBaseTransformOutOfPlaceAllocationFailureProbeResult swift_gst_test_base_transform_out_of_place_allocation_failure_probe(
    const gchar* factory_name,
    const gchar* type_name
);

SwiftGstTestBaseTransformModeValidationProbeResult swift_gst_test_base_transform_mode_validation_probe(void);

SwiftGstTestBaseTransformGeneralModeProbeResult swift_gst_test_base_transform_general_mode_probe(
    const gchar* in_place_factory_name,
    const gchar* in_place_type_name,
    const gchar* fixed_size_factory_name,
    const gchar* fixed_size_type_name,
    const gchar* general_factory_name,
    const gchar* general_type_name,
    const gchar* general_without_transform_factory_name,
    const gchar* general_without_transform_type_name
);

SwiftGstTestBaseTransformGeneralHookProbeResult swift_gst_test_base_transform_general_hook_probe(
    const gchar* factory_name,
    const gchar* type_name
);

SwiftGstTestBaseTransformSwiftHookInvocationResult swift_gst_test_base_transform_invoke_general_hooks(
    const gchar* factory_name
);

#ifdef __cplusplus
}
#endif

#endif /* CGSTREAMER_TEST_SUPPORT_H */
