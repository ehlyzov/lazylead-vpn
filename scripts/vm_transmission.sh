#!/usr/bin/env bash
# Run inside the Lima guest after mounting the Mac's Downloads directory.
set -euo pipefail

[[ "$(id -u)" == 0 ]] || { echo 'Run inside Lima with sudo.' >&2; exit 1; }
service_user="${1:?Usage: vm_transmission.sh GUEST_USER}"
[[ "$service_user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || exit 2
id "$service_user" >/dev/null
downloads=/mnt/mac-downloads
config=/var/lib/lazylead-transmission
[[ "$(findmnt -rn -M "$downloads" -o FSTYPE)" == virtiofs ]] || {
  echo 'The Mac Downloads virtiofs mount is required.' >&2
  exit 1
}
sudo -u "$service_user" test -w "$downloads"

# Keep the package's default daemon from starting on another address/user.
if systemctl is-active --quiet transmission-daemon.service; then
  echo 'An existing stock Transmission daemon is running; preserve it and migrate explicitly.' >&2
  exit 1
fi
systemctl mask transmission-daemon.service
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y transmission-daemon
systemctl stop lazylead-transmission.service 2>/dev/null || true
install -d -o "$service_user" -g "$(id -gn "$service_user")" -m 0700 "$config"

python3 - "$config/settings.json" "$service_user" <<'PY'
import json
import os
from pathlib import Path
import pwd
import sys

path = Path(sys.argv[1])
account = pwd.getpwnam(sys.argv[2])
settings = json.loads(path.read_text()) if path.exists() else {}
settings.update({
    'download-dir': '/mnt/mac-downloads',
    'incomplete-dir': '/mnt/mac-downloads/.transmission-incomplete',
    'incomplete-dir-enabled': True,
    'rename-partial-files': True,
    'trash-original-torrent-files': False,
    'watch-dir-enabled': False,
    'rpc-enabled': True,
    'rpc-bind-address': '127.0.0.1',
    'rpc-port': 9091,
    'rpc-authentication-required': False,
    'rpc-whitelist': '127.0.0.1',
    'rpc-whitelist-enabled': True,
    'rpc-host-whitelist': 'localhost',
    'rpc-host-whitelist-enabled': True,
    'port-forwarding-enabled': False,
    'lpd-enabled': False,
    'umask': 18,
})
temporary = path.with_suffix('.json.new')
temporary.write_text(json.dumps(settings, indent=2) + '\n')
temporary.chmod(0o600)
os.chown(temporary, account.pw_uid, account.pw_gid)
temporary.replace(path)
PY

cat > /etc/systemd/system/lazylead-transmission.service <<EOF
[Unit]
Description=Transmission with downloads on the Mac
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/mnt/mac-downloads
ConditionPathIsMountPoint=/mnt/mac-downloads

[Service]
Type=simple
User=$service_user
ExecStartPre=/usr/bin/test -w /mnt/mac-downloads
ExecStart=/usr/bin/transmission-daemon --foreground --config-dir /var/lib/lazylead-transmission
Restart=on-failure
RestartSec=5
TimeoutStopSec=60
NoNewPrivileges=true
UMask=0022

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now lazylead-transmission.service
systemctl is-active lazylead-transmission.service
