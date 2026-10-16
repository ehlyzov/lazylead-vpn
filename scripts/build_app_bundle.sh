#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-$(cat "${ROOT_DIR}/VERSION")}"
BUILD_REVISION="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)"
if ! git -C "$ROOT_DIR" diff --quiet HEAD --; then
  BUILD_REVISION="${BUILD_REVISION}-dirty"
fi
APP_DIR="${ROOT_DIR}/build/Lazylead VPN.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SCRIPTS_DIR="${RESOURCES_DIR}/scripts"

cd "${ROOT_DIR}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE="${BIN_DIR}/LazyleadVPN"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${SCRIPTS_DIR}"
swift "${ROOT_DIR}/scripts/generate_app_icon.swift"
cp "${EXECUTABLE}" "${MACOS_DIR}/LazyleadVPN"
cp "${ROOT_DIR}/build/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
cp "${ROOT_DIR}/host_checkpoint_gateway_route.sh" "${SCRIPTS_DIR}/"
cp "${ROOT_DIR}/host_corporate_routes.sh" "${SCRIPTS_DIR}/"
cp "${ROOT_DIR}/vm_corporate_router.sh" "${SCRIPTS_DIR}/"
chmod +x "${SCRIPTS_DIR}/host_checkpoint_gateway_route.sh"
chmod +x "${SCRIPTS_DIR}/host_corporate_routes.sh"
chmod +x "${SCRIPTS_DIR}/vm_corporate_router.sh"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LazyleadVPN</string>
    <key>CFBundleIdentifier</key>
    <string>io.lazylead.vpn</string>
    <key>CFBundleName</key>
    <string>Lazylead VPN</string>
    <key>CFBundleDisplayName</key>
    <string>Lazylead VPN</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LazyleadBuildRevision</key>
    <string>${BUILD_REVISION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "${APP_DIR}"
codesign --verify --strict "${APP_DIR}"
touch "${APP_DIR}"
echo "${APP_DIR}"
