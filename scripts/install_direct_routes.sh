#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET=/opt/lazylead-direct
LABEL=io.lazylead.direct-routes
PLIST="/Library/LaunchDaemons/$LABEL.plist"
[[ "$(id -u)" == 0 ]] || { echo "Run with sudo." >&2; exit 1; }
if [[ "${1:-}" == remove ]]; then
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  "$TARGET/host_routes.sh" remove
  rm -f "$PLIST"
  exit 0
fi
[[ $# == 0 ]] || exit 2

temporary_dir="$(mktemp -d /private/tmp/lazylead-routes.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
cp "$ROOT_DIR/build/direct-network/yandex-cloud-ipv4.txt" "$temporary_dir/routes.txt"
cp "$ROOT_DIR/scripts/host_direct_routes.sh" "$temporary_dir/host_routes.sh"
bash -n "$temporary_dir/host_routes.sh"
python3 - "$temporary_dir/routes.txt" <<'PY'
import ipaddress, pathlib, sys
path = pathlib.Path(sys.argv[1])
networks = [ipaddress.ip_network(line, strict=True) for line in path.read_text().splitlines()]
if not 40 <= len(networks) <= 2000:
    raise SystemExit('Unexpected number of Yandex Cloud prefixes')
if any(net.version != 4 or not net.is_global or net.prefixlen < 8 for net in networks):
    raise SystemExit('Non-public, overly broad or non-IPv4 prefix')
print('Validated', len(networks), 'public IPv4 prefixes')
PY
for directory in /opt "$TARGET"; do
  [[ ! -L "$directory" ]] || exit 1
  if [[ -e "$directory" ]]; then
    [[ "$(stat -f %u "$directory")" == 0 ]] || exit 1
    permissions="$(stat -f %Lp "$directory")"
    (( (8#$permissions & 0022) == 0 )) || exit 1
  fi
done
install -d -o root -g wheel -m 0755 "$TARGET" /var/log/lazylead-direct
install -o root -g wheel -m 0755 "$temporary_dir/host_routes.sh" "$TARGET/host_routes.sh"
install -o root -g wheel -m 0644 "$temporary_dir/routes.txt" "$TARGET/yandex-cloud-ipv4.txt"

cat > "$temporary_dir/routes.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.lazylead.direct-routes</string>
  <key>ProgramArguments</key><array>
    <string>/opt/lazylead-direct/host_routes.sh</string><string>install</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
  <key>UserName</key><string>root</string>
  <key>StandardOutPath</key><string>/var/log/lazylead-direct/routes.stdout.log</string>
  <key>StandardErrorPath</key><string>/var/log/lazylead-direct/routes.stderr.log</string>
</dict></plist>
PLIST
plutil -lint "$temporary_dir/routes.plist"
launchctl bootout "system/$LABEL" 2>/dev/null || true
"$TARGET/host_routes.sh" install
install -o root -g wheel -m 0644 "$temporary_dir/routes.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
cat /private/var/run/lazylead-direct-routes/status.txt
python3 - <<'PYVERIFY'
import socket
import subprocess
for host in ('api.cloud.yandex.net', 'console.yandex.cloud', 'storage.yandexcloud.net'):
    addresses = {row[4][0] for row in socket.getaddrinfo(host, 443, socket.AF_INET)}
    assert addresses, 'No IPv4 addresses for ' + host
    for address in addresses:
        route = subprocess.check_output(['/sbin/route', '-n', 'get', address], text=True)
        assert 'gateway: 192.168.64.2' in route, 'Route check failed for ' + host
result = subprocess.run(['/usr/bin/curl', '-4fsS', '--connect-timeout', '5', '--max-time', '15',
                         '-o', '/dev/null', 'https://api.cloud.yandex.net/endpoints'])
if result.returncode:
    raise SystemExit('Routes installed, but the Yandex API request failed. See docs/troubleshooting.md.')
print('VERIFIED: Yandex Cloud routes use Lima; Yandex API is reachable.')
PYVERIFY
