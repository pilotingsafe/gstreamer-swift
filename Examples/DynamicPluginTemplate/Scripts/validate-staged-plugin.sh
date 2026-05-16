#!/bin/sh
set -eu

plugin_id="${1:-swiftnative}"
factory_name="${3:-swiftnativeidentity}"
validation_timeout="${VALIDATION_TIMEOUT_SECONDS:-30}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
prefix="${2:-$template_root/.stage}"
"$script_dir/validate-plugin-id.sh" "$plugin_id" >/dev/null

case "$(uname -s)" in
    Darwin)
        plugin_library="$prefix/lib/gstreamer-1.0/libgst${plugin_id}.dylib"
        ;;
    Linux)
        plugin_library="$prefix/lib/gstreamer-1.0/libgst${plugin_id}.so"
        ;;
    *)
        echo "unsupported platform for staged validation" >&2
        exit 1
        ;;
esac

if [ ! -f "$plugin_library" ]; then
    echo "missing staged plugin library: $plugin_library" >&2
    echo "run from any directory: (cd \"$template_root\" && swiftly run swift build -c release && Scripts/stage-install.sh \"$plugin_id\" \"$prefix\")" >&2
    exit 1
fi

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "unavailable required tool: $1" >&2
        return 1
    fi
}

run_with_timeout() {
    seconds="$1"
    shift
    "$@" &
    pid="$!"
    (
        sleep "$seconds"
        kill "$pid" >/dev/null 2>&1 || true
    ) &
    watchdog="$!"

    status=0
    wait "$pid" || status="$?"
    kill "$watchdog" >/dev/null 2>&1 || true
    wait "$watchdog" >/dev/null 2>&1 || true

    case "$status" in
        137 | 143)
            echo "validation timed out after ${seconds}s: $*" >&2
            return 1
            ;;
        *)
            return "$status"
            ;;
    esac
}

prepend_env_path() {
    variable_name="$1"
    path_value="$2"

    if [ ! -d "$path_value" ]; then
        return 0
    fi

    eval "current_value=\${$variable_name:-}"
    case ":$current_value:" in
        *":$path_value:"*)
            ;;
        :)
            export "$variable_name=$path_value"
            ;;
        *)
            export "$variable_name=$path_value:$current_value"
            ;;
    esac
}

configure_macos_loader_environment() {
    if [ "$(uname -s)" != "Darwin" ]; then
        return 0
    fi

    for package in glib-2.0 gobject-2.0 gstreamer-1.0
    do
        libdir=$(pkg-config --variable=libdir "$package" 2>/dev/null || true)
        prepend_env_path DYLD_LIBRARY_PATH "$libdir"
        prepend_env_path DYLD_FALLBACK_LIBRARY_PATH "$libdir"
    done

    for package in gobject-introspection-1.0 gstreamer-1.0
    do
        typelibdir=$(pkg-config --variable=typelibdir "$package" 2>/dev/null || true)
        prepend_env_path GI_TYPELIB_PATH "$typelibdir"
    done
}

require_tool swiftly || exit 1
require_tool pkg-config || exit 1
require_tool gst-inspect-1.0 || exit 1
require_tool gst-launch-1.0 || exit 1

if ! pkg-config --atleast-version=1.28.2 gstreamer-1.0; then
    echo "missing GStreamer 1.28.2 or newer" >&2
    exit 1
fi
configure_macos_loader_environment

registry="${TMPDIR:-/tmp}/gst-swiftnative-registry-$$.bin"
rm -f "$registry"

export GST_PLUGIN_PATH="$prefix/lib/gstreamer-1.0"
export GST_REGISTRY="$registry"

if [ "${EXPECT_FAILURE_DIAGNOSTIC:-0}" = "1" ]; then
    set +e
    SWIFT_NATIVE_DYNAMIC_PLUGIN_FORCE_REGISTRATION_FAILURE=1
    export SWIFT_NATIVE_DYNAMIC_PLUGIN_FORCE_REGISTRATION_FAILURE
    diagnostic_output=$(run_with_timeout "$validation_timeout" gst-inspect-1.0 "$plugin_id" 2>&1)
    diagnostic_status="$?"
    unset SWIFT_NATIVE_DYNAMIC_PLUGIN_FORCE_REGISTRATION_FAILURE
    set -e

    printf '%s\n' "$diagnostic_output"
    if [ "$diagnostic_status" -eq 0 ]; then
        echo "expected gst-inspect-1.0 failure diagnostic but inspection succeeded" >&2
        rm -f "$registry"
        exit 1
    fi
    printf '%s\n' "$diagnostic_output" | grep "forced Swift dynamic plugin registration failure" >/dev/null || {
        echo "missing useful Swift registration failure diagnostic" >&2
        rm -f "$registry"
        exit 1
    }
    rm -f "$registry"
    echo "failure diagnostic validated through gst-inspect-1.0"
    exit 0
fi

run_with_timeout "$validation_timeout" gst-inspect-1.0 "$plugin_id"
run_with_timeout "$validation_timeout" gst-inspect-1.0 "$factory_name"
run_with_timeout "$validation_timeout" gst-launch-1.0 -q videotestsrc num-buffers=1 ! "$factory_name" ! fakesink

rm -f "$registry"
echo "external discovery validated with GST_PLUGIN_PATH=$GST_PLUGIN_PATH and GST_REGISTRY=$GST_REGISTRY"
