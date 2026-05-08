#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${LAZYLEAD_VPN_CONFIG:-/usr/local/etc/lazylead-vpn/env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

CORP_ROUTES=("10.0.0.0 255.0.0.0 10.0.0.1")
DNS_DOMAINS=("corp.example.com")
DNS_SERVERS=("10.0.0.53")

if [[ -n "${VPN_CORPORATE_ROUTES:-}" ]]; then
  IFS=';' read -r -a CORP_ROUTES <<< "${VPN_CORPORATE_ROUTES}"
fi

if [[ -n "${VPN_DNS_DOMAINS:-}" ]]; then
  read -r -a DNS_DOMAINS <<< "${VPN_DNS_DOMAINS//,/ }"
fi

if [[ -n "${VPN_DNS_SERVERS:-}" ]]; then
  read -r -a DNS_SERVERS <<< "${VPN_DNS_SERVERS//,/ }"
fi

usage() {
  cat <<'USAGE'
Usage:
  sudo ./host_corporate_routes.sh install <vm_ip>
  sudo ./host_corporate_routes.sh remove <vm_ip>
  ./host_corporate_routes.sh status <vm_ip>

Example:
  sudo ./host_corporate_routes.sh install 192.168.64.10
  ./host_corporate_routes.sh status 192.168.64.10
  sudo ./host_corporate_routes.sh remove 192.168.64.10

This configures the macOS host to route corporate networks
through a Linux VM that is connected to Check Point.

Environment:
  LAZYLEAD_VPN_CONFIG=/path/env
  VPN_CORPORATE_ROUTES="10.0.0.0 255.0.0.0 10.0.0.1;172.16.0.0 255.240.0.0 172.16.0.1"
  VPN_DNS_DOMAINS="corp.example.com internal.example.com"
  VPN_DNS_SERVERS="10.0.0.53 10.0.0.54"
USAGE
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

mode="$1"
vm_ip="$2"

require_root_for_changes() {
  if [[ "${mode}" != "status" && "$(id -u)" -ne 0 ]]; then
    echo "Run '${mode}' with sudo." >&2
    exit 1
  fi
}

clear_probe_cache() {
  local probe_ip="$1"

  route -n delete -host "$probe_ip" >/dev/null 2>&1 || true
  arp -d "$probe_ip" >/dev/null 2>&1 || true
}

route_add_or_change() {
  local network="$1"
  local netmask="$2"
  local probe_ip="$3"

  clear_probe_cache "$probe_ip"
  route -n delete -net "$network" -netmask "$netmask" >/dev/null 2>&1 || true
  route -n add -net "$network" -netmask "$netmask" "$vm_ip"
  clear_probe_cache "$probe_ip"
}

route_delete() {
  local network="$1"
  local netmask="$2"

  route -n delete -net "$network" -netmask "$netmask" "$vm_ip" >/dev/null 2>&1 \
    || route -n delete -net "$network" -netmask "$netmask" >/dev/null 2>&1 \
    || true
}

install_resolvers() {
  mkdir -p /etc/resolver

  for domain in "${DNS_DOMAINS[@]}"; do
    {
      for dns in "${DNS_SERVERS[@]}"; do
        echo "nameserver ${dns}"
      done
      echo "timeout 2"
    } > "/etc/resolver/${domain}"
  done
}

remove_resolvers() {
  for domain in "${DNS_DOMAINS[@]}"; do
    rm -f "/etc/resolver/${domain}"
  done
}

status() {
  echo "VM gateway: ${vm_ip}"
  echo
  echo "Routes:"
  for route_spec in "${CORP_ROUTES[@]}"; do
    read -r network netmask probe_ip <<< "$route_spec"
    echo "--- ${network}/${netmask} probe ${probe_ip}"
    route -n get "$probe_ip" 2>&1 || true
  done

  echo
  echo "Resolvers:"
  for domain in "${DNS_DOMAINS[@]}"; do
    echo "--- /etc/resolver/${domain}"
    if [[ -f "/etc/resolver/${domain}" ]]; then
      cat "/etc/resolver/${domain}"
    else
      echo "missing"
    fi
  done

  echo
  echo "DNS summary:"
  scutil --dns | awk '
    /resolver #/ {resolver=$0}
    /domain|search domain|nameserver|if_index/ {
      print resolver
      resolver=""
      print
    }
  '
}

require_root_for_changes

case "$mode" in
  install)
    for route_spec in "${CORP_ROUTES[@]}"; do
      read -r network netmask probe_ip <<< "$route_spec"
      route_add_or_change "$network" "$netmask" "$probe_ip"
    done
    install_resolvers
    dscacheutil -flushcache || true
    killall -HUP mDNSResponder 2>/dev/null || true
    status
    ;;
  remove)
    for route_spec in "${CORP_ROUTES[@]}"; do
      read -r network netmask _ <<< "$route_spec"
      route_delete "$network" "$netmask"
    done
    remove_resolvers
    dscacheutil -flushcache || true
    killall -HUP mDNSResponder 2>/dev/null || true
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
