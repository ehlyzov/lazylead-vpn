#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${LAZYLEAD_VPN_CONFIG:-/usr/local/etc/lazylead-vpn/env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

ROUTE_PROBES=("10.0.0.1" "10.0.0.53")

if [[ -n "${VPN_ROUTE_PROBES:-}" ]]; then
  read -r -a ROUTE_PROBES <<< "${VPN_ROUTE_PROBES//,/ }"
fi

usage() {
  cat <<'USAGE'
Usage inside Linux VM, after Check Point/SNX is connected:
  sudo ./vm_corporate_router.sh install <host_facing_if> [vpn_if]
  sudo ./vm_corporate_router.sh remove <host_facing_if> [vpn_if]
  ./vm_corporate_router.sh status [host_facing_if] [vpn_if]

Examples:
  ip -br addr
  ip route get 10.0.0.1
  sudo ./vm_corporate_router.sh install enp0s1 tun0

host_facing_if:
  VM interface reachable from macOS host.

vpn_if:
  Check Point/SNX tunnel interface. If omitted, the script tries to detect it
  from VPN_ROUTE_PROBES.

Environment:
  LAZYLEAD_VPN_CONFIG=/path/env
  VPN_ROUTE_PROBES="10.0.0.1 10.0.0.53"
USAGE
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 2
fi

mode="$1"
host_if="${2:-}"
vpn_if="${3:-}"

if [[ "$mode" == "status" && -z "$host_if" ]]; then
  host_if="<not-set>"
fi

require_root_for_changes() {
  if [[ "${mode}" != "status" && "$(id -u)" -ne 0 ]]; then
    echo "Run '${mode}' with sudo." >&2
    exit 1
  fi
}

detect_vpn_if() {
  local target dev
  for target in "${ROUTE_PROBES[@]}"; do
    dev="$(ip route get "$target" 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
    if [[ -n "$dev" && "$dev" != "$host_if" ]]; then
      echo "$dev"
      return 0
    fi
  done
  return 1
}

ensure_vpn_if() {
  if [[ -z "$vpn_if" ]]; then
    vpn_if="$(detect_vpn_if || true)"
  fi
  if [[ -z "$vpn_if" ]]; then
    echo "Could not detect VPN interface. Pass it explicitly, for example: tun0, snx0, ppp0." >&2
    exit 1
  fi
}

install_iptables() {
  iptables -t nat -C POSTROUTING -o "$vpn_if" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -o "$vpn_if" -j MASQUERADE

  iptables -C FORWARD -i "$host_if" -o "$vpn_if" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "$host_if" -o "$vpn_if" -j ACCEPT

  iptables -C FORWARD -i "$vpn_if" -o "$host_if" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "$vpn_if" -o "$host_if" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

remove_iptables() {
  iptables -t nat -D POSTROUTING -o "$vpn_if" -j MASQUERADE 2>/dev/null || true
  iptables -D FORWARD -i "$host_if" -o "$vpn_if" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$vpn_if" -o "$host_if" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
}

status() {
  echo "host_if: ${host_if}"
  echo "vpn_if: ${vpn_if:-$(detect_vpn_if 2>/dev/null || echo '<not-detected>')}"
  echo
  echo "Addresses:"
  ip -br addr
  echo
  echo "Corporate route probes:"
  for target in "${ROUTE_PROBES[@]}"; do
    echo "--- ${target}"
    ip route get "$target" 2>&1 || true
  done
  echo
  echo "Forwarding:"
  sysctl net.ipv4.ip_forward
  echo
  echo "iptables NAT:"
  iptables -t nat -S POSTROUTING 2>/dev/null || true
  echo
  echo "iptables FORWARD:"
  iptables -S FORWARD 2>/dev/null || true
}

require_root_for_changes

case "$mode" in
  install)
    if [[ -z "$host_if" ]]; then
      usage
      exit 2
    fi
    ensure_vpn_if
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w "net.ipv4.conf.${host_if}.forwarding=1" || true
    sysctl -w "net.ipv4.conf.${vpn_if}.forwarding=1" || true
    sysctl -w "net.ipv4.conf.${host_if}.rp_filter=0" || true
    sysctl -w "net.ipv4.conf.${vpn_if}.rp_filter=0" || true
    install_iptables
    status
    ;;
  remove)
    if [[ -z "$host_if" ]]; then
      usage
      exit 2
    fi
    ensure_vpn_if
    remove_iptables
    status
    ;;
  status)
    status
    ;;
  *)
    usage
    exit 2
    ;;
esac
