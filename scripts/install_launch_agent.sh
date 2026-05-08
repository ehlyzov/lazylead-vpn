#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/build/Lazylead VPN.app}"
LABEL="io.lazylead.vpn.autostart"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_VALUE="$(id -u)"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found: ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${HOME}/Library/LaunchAgents"

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>${APP_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/Lazylead VPN/launchagent.out.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/Lazylead VPN/launchagent.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "${PLIST}" >/dev/null

launchctl bootout "gui/${UID_VALUE}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${UID_VALUE}" "${PLIST}"
launchctl enable "gui/${UID_VALUE}/${LABEL}"

echo "Installed ${PLIST}"
echo "Autostart target: ${APP_PATH}"
