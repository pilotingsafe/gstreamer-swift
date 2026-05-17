#ifndef SWIFT_NATIVE_DYNAMIC_PLUGIN_ENTRYPOINT_H
#define SWIFT_NATIVE_DYNAMIC_PLUGIN_ENTRYPOINT_H

#include <gst/gst.h>

#ifdef __cplusplus
extern "C" {
#endif

gboolean swift_native_dynamic_plugin_init(GstPlugin* plugin);
void swift_native_dynamic_plugin_link_anchor(void);
void swift_native_dynamic_plugin_record_status_error(GstPlugin* plugin, const gchar* message);

#ifdef __cplusplus
}
#endif

#endif /* SWIFT_NATIVE_DYNAMIC_PLUGIN_ENTRYPOINT_H */
