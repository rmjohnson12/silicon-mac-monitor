#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
swift build -c release --build-system native
BUILD_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/silicon-build.XXXXXX")"
trap 'rm -rf "$BUILD_TMP_DIR"' EXIT
# Sign outside cloud-synced source folders: file providers can restore Finder
# metadata immediately after xattr cleanup and cause codesign to reject it.
APP_DIR="$BUILD_TMP_DIR/Silicon.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_DIR/.build/AppIcon.iconset"
cp "$PROJECT_DIR/.build/release/Silicon" "$APP_DIR/Contents/MacOS/Silicon"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
swift "$PROJECT_DIR/scripts/make-icon.swift" "$PROJECT_DIR/.build/AppIcon-1024.png"
for ICON_SIZE in 16 32 128 256 512; do
    sips -z "$ICON_SIZE" "$ICON_SIZE" "$PROJECT_DIR/.build/AppIcon-1024.png" --out "$PROJECT_DIR/.build/AppIcon.iconset/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((ICON_SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$PROJECT_DIR/.build/AppIcon-1024.png" --out "$PROJECT_DIR/.build/AppIcon.iconset/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Silicon</string>
<key>CFBundleDisplayName</key><string>Silicon</string>
<key>CFBundleExecutable</key><string>Silicon</string>
<key>CFBundleIdentifier</key><string>local.ronniejohnson.Silicon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
xattr -cr "$APP_DIR"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
mkdir -p "$PROJECT_DIR/dist"
ditto --norsrc --noextattr "$APP_DIR" "$PROJECT_DIR/dist/Silicon.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
APP_ARCH="$(uname -m)"
ARCHIVE_PATH="$PROJECT_DIR/dist/Silicon-$APP_VERSION-$APP_ARCH.zip"
# Archive the verified temporary bundle, without file-provider/Finder metadata.
ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$ARCHIVE_PATH"
print "Built: $PROJECT_DIR/dist/Silicon.app"
print "Packaged: $ARCHIVE_PATH"
