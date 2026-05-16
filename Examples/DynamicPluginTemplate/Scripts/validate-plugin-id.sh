#!/bin/sh
set -eu

plugin_id="${1:-swiftnative}"

case "$plugin_id" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* | [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_]* | "")
        echo "invalid plugin ID: $plugin_id" >&2
        echo "plugin IDs must start with an ASCII letter or '_' and contain only ASCII letters, digits, or '_'" >&2
        exit 1
        ;;
esac

artifact_stem="libgst${plugin_id}"
echo "plugin ID: $plugin_id"
echo "artifact stem: $artifact_stem"
echo "macOS artifact: ${artifact_stem}.dylib"
echo "Linux artifact: ${artifact_stem}.so"
