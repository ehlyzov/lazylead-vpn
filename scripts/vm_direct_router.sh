#!/usr/bin/env bash
set -euo pipefail

[[ "$(id -u)" == 0 ]] || { echo "Run inside Lima with sudo." >&2; exit 1; }
ip link show lima0 >/dev/null
ip link show direct0 >/dev/null

# Only forward traffic from this Mac. The guest's own connections are unaffected.
iptables -N LAZYLEAD_DIRECT 2>/dev/null || true
iptables -F LAZYLEAD_DIRECT
iptables -A LAZYLEAD_DIRECT -i lima0 -o direct0 -s 192.168.64.1/32 -j ACCEPT
iptables -A LAZYLEAD_DIRECT -i direct0 -o lima0 -d 192.168.64.1/32 \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A LAZYLEAD_DIRECT -j REJECT
iptables -C FORWARD -j LAZYLEAD_DIRECT 2>/dev/null || iptables -I FORWARD 1 -j LAZYLEAD_DIRECT
iptables -t nat -C POSTROUTING -s 192.168.64.1/32 -o direct0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 192.168.64.1/32 -o direct0 -j MASQUERADE
sysctl -w net.ipv4.ip_forward=1
