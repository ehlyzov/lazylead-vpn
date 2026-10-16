#!/usr/bin/env bash
set -euo pipefail

# Executed inside the guest, after attaching the direct0 bridged interface.
# Keep eth0 for Lima management and lima0 for traffic from the Mac, but do
# not let either use the host's Pepper VPN as an internet fallback.
[[ "$(id -u)" == 0 ]] || { echo "Run inside Lima with sudo." >&2; exit 1; }
ip link show direct0 >/dev/null
test -f /etc/netplan/50-cloud-init.yaml

python3 - <<'PY'
import pathlib
import shutil
import yaml

path = pathlib.Path('/etc/netplan/50-cloud-init.yaml')
config = yaml.safe_load(path.read_text())
interfaces = config['network']['ethernets']
if not all(name in interfaces for name in ('eth0', 'lima0', 'direct0')):
    raise SystemExit('Expected eth0, lima0 and direct0 in the Lima netplan config')
backup = path.with_suffix('.yaml.before-direct')
if not backup.exists():
    shutil.copy2(path, backup)
for name in ('eth0', 'lima0'):
    interface = interfaces[name]
    interface.pop('nameservers', None)
    interface['dhcp4-overrides'] = {'use-routes': False, 'use-dns': False}
    interface['dhcp6'] = False
    interface['accept-ra'] = False
interfaces['direct0']['dhcp4-overrides'] = {'route-metric': 50, 'use-dns': True}
interfaces['direct0']['dhcp4'] = True
path.write_text(yaml.safe_dump(config, sort_keys=False))
path.chmod(0o600)
PY
netplan generate
netplan apply
if systemctl cat snx-rs.service >/dev/null 2>&1; then
  systemctl disable --now snx-rs.service
fi
echo "Default routes (only direct0 should provide internet access):"
ip -4 route show default
resolvectl dns
