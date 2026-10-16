#!/usr/bin/env bash
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Run inside Lima with sudo.' >&2; exit 1; }
ip -4 address show dev lima0 | grep -q '192.168.64.2/'
install -d -m 0755 /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/lazylead-domain-dns.conf <<'EOF'
[Resolve]
DNSStubListenerExtra=192.168.64.2:1053
EOF
systemctl restart systemd-resolved
ss -lunt 'sport = :1053'
