#include "GStreamerBaseShimInternal.h"

#include <stdarg.h>

G_GNUC_INTERNAL gboolean swift_gst_base_sink_fail(gchar** error_message, const gchar* format, ...) {
    if (error_message != NULL) {
        va_list args;
        va_start(args, format);
        *error_message = g_strdup_vprintf(format, args);
        va_end(args);
    }

    return FALSE;
}

G_GNUC_INTERNAL gboolean swift_gst_base_sink_is_non_empty(const gchar* value) {
    return value != NULL && value[0] != '\0';
}

G_GNUC_INTERNAL gboolean swift_gst_base_sink_is_valid_factory_name(const gchar* name) {
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

G_GNUC_INTERNAL gboolean swift_gst_base_sink_is_valid_type_name(const gchar* name) {
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

const gchar* swift_gst_plugin_name(GstPlugin* plugin) {
    return plugin != NULL ? gst_plugin_get_name(plugin) : NULL;
}

gboolean swift_gst_element_factory_plugin_name_matches(
    const gchar* factory_name,
    const gchar* expected_plugin_name
) {
    if (factory_name == NULL || expected_plugin_name == NULL) {
        return FALSE;
    }

    GstElementFactory* factory = gst_element_factory_find(factory_name);
    if (factory == NULL) {
        return FALSE;
    }

    const gchar* plugin_name = gst_plugin_feature_get_plugin_name(GST_PLUGIN_FEATURE(factory));
    gboolean result = g_strcmp0(plugin_name, expected_plugin_name) == 0;
    gst_object_unref(factory);
    return result;
}

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
