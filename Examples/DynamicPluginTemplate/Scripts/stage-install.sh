#!/bin/sh
set -eu

plugin_id="${1:-swiftnative}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
prefix="${2:-$template_root/.stage}"

# Default checked-in artifacts: libgstswiftnative.dylib and libgstswiftnative.so.
# Symbol inspection examples:
# nm -gU .build/release/libgstswiftnative.dylib | grep swift_native_dynamic_plugin_init
# nm -gU .build/release/libgstswiftnative.dylib | grep gst_plugin_swiftnative_get_desc
# nm -D .build/release/libgstswiftnative.so | grep swift_native_dynamic_plugin_init
# nm -D .build/release/libgstswiftnative.so | grep gst_plugin_swiftnative_get_desc

"$script_dir/validate-plugin-id.sh" "$plugin_id" >/dev/null

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "missing required tool: $1" >&2
        return 1
    fi
}

require_tool swiftly || exit 1
require_tool pkg-config || exit 1

if ! pkg-config --atleast-version=1.28.2 gstreamer-1.0; then
    echo "missing GStreamer 1.28.2 or newer for dynamic plugin validation" >&2
    exit 1
fi

target_info=$(cd "$template_root" && swiftly run swift -print-target-info)
echo "$target_info" | grep runtimeLibraryPaths >/dev/null || {
    echo "missing runtimeLibraryPaths in swift target info" >&2
    exit 1
}
echo "$target_info" | grep runtimeResourcePath >/dev/null || {
    echo "missing runtimeResourcePath in swift target info" >&2
    exit 1
}
runtime_library_paths=$(printf '%s\n' "$target_info" | awk '
    /"runtimeLibraryPaths"/ { in_paths = 1; next }
    in_paths && /\]/ { in_paths = 0; next }
    in_paths {
        gsub(/[",]/, "")
        gsub(/^[[:space:]]*/, "")
        if (length($0) > 0) print $0
    }
')
runtime_resource_path=$(printf '%s\n' "$target_info" | awk -F'"' '/"runtimeResourcePath"/ { print $4; exit }')

plugin_dir="$prefix/lib/gstreamer-1.0"
swift_dir="$prefix/lib/swift"
mkdir -p "$plugin_dir" "$swift_dir"
if [ ! -d "$template_root/.build/release" ]; then
    echo "missing release build directory: $template_root/.build/release" >&2
    echo "run from any directory: (cd \"$template_root\" && swiftly run swift build -c release)" >&2
    exit 1
fi
release_dir=$(cd "$template_root/.build/release" && pwd -P)

copy_swift_runtime_libraries() {
    extension="$1"
    for runtime_path in $runtime_library_paths "$runtime_resource_path"
    do
        if [ -d "$runtime_path" ]; then
            find "$runtime_path" -maxdepth 1 -type f -name "libswift*.$extension" -exec cp {} "$swift_dir/" \;
        fi
    done
}

copy_private_swiftpm_libraries() {
    extension="$1"
    find "$release_dir" -type f -name "*.$extension" ! -name "libgst${plugin_id}.$extension" | while IFS= read -r library
    do
        case "$(basename "$library")" in
            libgst*.dylib | libgst*.so)
                ;;
            *)
                cp "$library" "$swift_dir/"
                ;;
        esac
    done
}

dependency_basename() {
    basename "$1" | sed 's/ (.*//'
}

private_library_exists() {
    dependency="$(dependency_basename "$1")"
    test -f "$swift_dir/$dependency" || find "$release_dir" -type f -name "$dependency" | grep . >/dev/null
}

classify_dependency() {
    dependency="$1"
    case "$dependency" in
        "" | "$plugin_library" | @executable_path/*)
            return 0
            ;;
        @loader_path/../swift/* | '$ORIGIN'/../swift/*)
            return 0
            ;;
        /System/Library/* | /usr/lib/* | /lib/* | /lib64/* | /usr/lib64/*)
            return 0
            ;;
        *libgst* | *libgstreamer* | *libgobject* | *libglib* | *libgio* | *libgmodule* | *libintl* | *gettext*)
            return 0
            ;;
        *libc.* | *libSystem* | *libpthread* | *libdl.* | *ld-linux* | linux-vdso*)
            return 0
            ;;
        *libswift*)
            return 0
            ;;
        @rpath/* | *.dylib | *.so | *.so.*)
            if private_library_exists "$dependency"; then
                return 0
            fi
            echo "unclassified dependency: $dependency" >&2
            return 1
            ;;
        *)
            echo "unclassified dependency: $dependency" >&2
            return 1
            ;;
    esac
}

classify_macos_dependencies() {
    otool -L "$plugin_library" | tail -n +2 | awk '{print $1}' | while IFS= read -r dependency
    do
        classify_dependency "$dependency" || exit 1
    done
}

classify_linux_dependencies() {
    ldd "$plugin_library" | while IFS= read -r line
    do
        dependency=$(printf '%s\n' "$line" | awk '{ if ($2 == "=>") print $3; else print $1 }')
        case "$dependency" in
            "not")
                dependency=$(printf '%s\n' "$line" | awk '{print $1}')
                ;;
        esac
        classify_dependency "$dependency" || exit 1
    done
}

case "$(uname -s)" in
    Darwin)
        plugin_library="$release_dir/libgst${plugin_id}.dylib"
        if [ ! -f "$plugin_library" ]; then
            echo "missing built plugin library: $plugin_library" >&2
            echo "run from any directory: (cd \"$template_root\" && swiftly run swift build -c release)" >&2
            exit 1
        fi
        swift-stdlib-tool --copy --scan-executable "$plugin_library" --platform macosx --destination "$swift_dir" || {
            echo "swift-stdlib-tool unavailable or failed; copy Swift runtime libraries manually" >&2
            exit 1
        }
        copy_swift_runtime_libraries dylib
        copy_private_swiftpm_libraries dylib
        otool -L "$plugin_library"
        classify_macos_dependencies
        if ! otool -l "$plugin_library" | grep "@loader_path/../swift" >/dev/null; then
            install_name_tool -add_rpath "@loader_path/../swift" "$plugin_library"
        fi
        otool -l "$plugin_library"
        otool -l "$plugin_library" | grep "@loader_path/../swift" >/dev/null || {
            echo "missing required @loader_path/../swift rpath after install_name_tool" >&2
            exit 1
        }
        codesign --force --sign - "$plugin_library"
        codesign --verify "$plugin_library"
        ;;
    Linux)
        plugin_library="$release_dir/libgst${plugin_id}.so"
        if [ ! -f "$plugin_library" ]; then
            echo "missing built plugin library: $plugin_library" >&2
            echo "run from any directory: (cd \"$template_root\" && swiftly run swift build -c release)" >&2
            exit 1
        fi
        copy_swift_runtime_libraries so
        copy_private_swiftpm_libraries so
        ldd "$plugin_library"
        classify_linux_dependencies
        if ! command -v patchelf >/dev/null 2>&1; then
            echo "patchelf unavailable; cannot configure $ORIGIN/../swift rpath automatically" >&2
            exit 1
        fi
        patchelf --set-rpath '$ORIGIN/../swift' "$plugin_library"
        ;;
    *)
        echo "unsupported platform for staged install" >&2
        exit 1
        ;;
esac

echo "GStreamer and GLib are external system dependencies and are not bundled."
cp "$plugin_library" "$plugin_dir/"
echo "staged install prefix: $prefix"
echo "plugin path: $plugin_dir"
echo "swift library path: $swift_dir"
