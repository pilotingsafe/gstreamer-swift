#include "SwiftNativeDynamicPluginEntrypoint.h"

#ifndef PACKAGE
#define PACKAGE "swiftnative"
#endif

void swift_native_dynamic_plugin_link_anchor(void) {}

void swift_native_dynamic_plugin_record_status_error(GstPlugin* plugin, const gchar* message) {
    if (plugin == NULL || message == NULL || message[0] == '\0') {
        return;
    }

    gst_plugin_add_status_error(plugin, message);
}

static gboolean swiftnative_plugin_init(GstPlugin* plugin) {
    swift_native_dynamic_plugin_link_anchor();
    return swift_native_dynamic_plugin_init(plugin);
}

GST_PLUGIN_DEFINE(
    GST_VERSION_MAJOR,
    GST_VERSION_MINOR,
    swiftnative,
    "Swift native dynamic plugin",
    swiftnative_plugin_init,
    "0.1.0",
    "MIT",
    PACKAGE,
    "https://example.invalid/swiftnative"
)
