#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/MacRo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

build_archs=()
case "$(uname -m)" in
    arm64)
        build_archs=(arm64 x86_64)
        ;;
    x86_64)
        build_archs=(x86_64)
        ;;
    *)
        build_archs=("$(uname -m)")
        ;;
esac

build_binary_for_arch() {
    local arch="$1"
    swift build -c release --arch "$arch" >/dev/null
    echo "$ROOT_DIR/.build/${arch}-apple-macosx/release/MacRo"
}

generate_app_icon() {
    local source_png="$ROOT_DIR/Resources/AppIcon.png"
    local output_icns="$RESOURCES_DIR/AppIcon.icns"
    local iconset_parent
    local iconset

    if [[ ! -f "$source_png" ]]; then
        echo "Missing app icon source: $source_png" >&2
        return 1
    fi

    iconset_parent="$(mktemp -d "${TMPDIR:-/tmp}/macro-iconset.XXXXXX")"
    iconset="$iconset_parent/AppIcon.iconset"
    mkdir -p "$iconset"
    trap 'rm -rf "$iconset_parent"' RETURN

    sips -z 16 16 "$source_png" --out "$iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$source_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$source_png" --out "$iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$source_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$source_png" --out "$iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$source_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$source_png" --out "$iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$source_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$source_png" --out "$iconset/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$source_png" --out "$iconset/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$iconset" -o "$output_icns"
}

cd "$ROOT_DIR"

pids=()
binary_paths=()
for arch in "${build_archs[@]}"; do
    binary_paths+=("$ROOT_DIR/.build/${arch}-apple-macosx/release/MacRo")
    build_binary_for_arch "$arch" &
    pids+=($!)
done
for pid in "${pids[@]}"; do
    wait "$pid"
done
binaries=("${binary_paths[@]}")

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
find "$ROOT_DIR/Resources" -type f ! -name Info.plist -exec cp {} "$RESOURCES_DIR/" \;
generate_app_icon

if ((${#binaries[@]} == 1)); then
    cp "${binaries[0]}" "$MACOS_DIR/MacRo"
else
    lipo -create "${binaries[@]}" -output "$MACOS_DIR/MacRo"
fi

chmod +x "$MACOS_DIR/MacRo"

if [[ -n "${MACRO_CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$MACRO_CODESIGN_IDENTITY" "$APP_DIR"
fi

echo "Packaged: $APP_DIR"
