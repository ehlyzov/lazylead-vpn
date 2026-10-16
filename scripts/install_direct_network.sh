#!/usr/bin/env bash
set -euo pipefail

# Install the official socket_vmnet release as a dedicated bridged network.
# Run with sudo once; Lima itself continues to run as the normal user.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ROOT_DIR}/build/socket_vmnet-1.2.2-arm64.tar.gz"
ARCHIVE_SHA256="c7bf62308fbcfdc29bdfb8373c9b1951f7ac2396446e4390919796a94972e6dc"
LABEL="io.lazylead.direct-network"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
BINARY="/opt/socket_vmnet/bin/socket_vmnet"

[[ "$(id -u)" == 0 ]] || { echo "Run this installer with sudo." >&2; exit 1; }
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || exit 1
[[ -f "$ARCHIVE" ]] || {
  echo "Download the official release first:" >&2
  echo "https://github.com/lima-vm/socket_vmnet/releases/download/v1.2.2/socket_vmnet-1.2.2-arm64.tar.gz" >&2
  echo "Save it as: $ARCHIVE" >&2
  exit 1
}
/sbin/ifconfig en0 >/dev/null

temporary_dir="$(mktemp -d /private/tmp/lazylead-direct.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
cp "$ARCHIVE" "$temporary_dir/release.tar.gz"
actual_sha256="$(shasum -a 256 "$temporary_dir/release.tar.gz" | awk '{print $1}')"
[[ "$actual_sha256" == "$ARCHIVE_SHA256" ]] || {
  echo "socket_vmnet release checksum mismatch; no system changes made." >&2
  exit 1
}
tar xzf "$temporary_dir/release.tar.gz" -C "$temporary_dir" ./opt/socket_vmnet/bin/socket_vmnet
staged_binary="$temporary_dir/opt/socket_vmnet/bin/socket_vmnet"
if [[ -e "$BINARY" ]] && ! cmp -s "$BINARY" "$staged_binary"; then
  echo "An existing different socket_vmnet installation needs review: $BINARY" >&2
  exit 1
fi

cat > "$temporary_dir/service.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.lazylead.direct-network</string>
  <key>ProgramArguments</key><array>
    <string>/opt/socket_vmnet/bin/socket_vmnet</string>
    <string>--vmnet-mode=bridged</string>
    <string>--vmnet-interface=en0</string>
    <string>--socket-group=staff</string>
    <string>/private/var/run/lazylead-direct.sock</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>UserName</key><string>root</string>
  <key>StandardOutPath</key><string>/var/log/lazylead-direct/stdout.log</string>
  <key>StandardErrorPath</key><string>/var/log/lazylead-direct/stderr.log</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$temporary_dir/service.plist"

# Refuse symlinked or user-writable executable parents.
for directory in /opt /opt/socket_vmnet /opt/socket_vmnet/bin; do
  [[ ! -L "$directory" ]] || { echo "Unexpected symlink: $directory" >&2; exit 1; }
  if [[ -e "$directory" ]]; then
    [[ "$(stat -f %u "$directory")" == 0 ]] || { echo "Not root-owned: $directory" >&2; exit 1; }
    permissions="$(stat -f %Lp "$directory")"
    (( (8#$permissions & 0022) == 0 )) || { echo "Writable by others: $directory" >&2; exit 1; }
  fi
done
install -d -o root -g wheel -m 0755 /opt/socket_vmnet/bin /var/log/lazylead-direct
install -o root -g wheel -m 0755 "$staged_binary" "$BINARY"
if [[ -f "$PLIST" ]]; then
  cp -p "$PLIST" "${PLIST}.backup-$(date +%Y%m%d-%H%M%S)"
fi
install -o root -g wheel -m 0644 "$temporary_dir/service.plist" "$PLIST"
launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
for attempt in {1..10}; do
  if [[ -S /private/var/run/lazylead-direct.sock ]]; then
    echo "Direct bridged network is ready on en0. Lima configuration can now be applied."
    exit 0
  fi
  sleep 1
done
echo "Network service did not create its socket. See /var/log/lazylead-direct/stderr.log." >&2
exit 1
