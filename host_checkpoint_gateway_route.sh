#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${LAZYLEAD_VPN_CONFIG:-/usr/local/etc/lazylead-vpn/env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

BOOTSTRAP_HOSTS=("vpn.example.com" "sso.example.com")
PUBLIC_DNS_SERVERS=("1.1.1.1" "9.9.9.9")

if [[ -n "${VPN_BOOTSTRAP_HOSTS:-}" ]]; then
  read -r -a BOOTSTRAP_HOSTS <<< "${VPN_BOOTSTRAP_HOSTS//,/ }"
fi

if [[ -n "${VPN_PUBLIC_DNS_SERVERS:-}" ]]; then
  read -r -a PUBLIC_DNS_SERVERS <<< "${VPN_PUBLIC_DNS_SERVERS//,/ }"
fi

if [[ -n "${VPN_HOST:-}" ]]; then
  BOOTSTRAP_HOSTS=("${VPN_HOST}")
fi

usage() {
  cat <<'USAGE'
Usage:
  sudo ./host_checkpoint_gateway_route.sh install
  sudo ./host_checkpoint_gateway_route.sh remove
  ./host_checkpoint_gateway_route.sh status

Purpose:
  Force the Check Point gateway itself to go through the normal Wi-Fi/LAN
  gateway instead of another VPN. This is only for bootstrapping the
  Check Point tunnel inside the VM.

Environment:
  LAZYLEAD_VPN_CONFIG=/path/env  Optional env file to source.
  VPN_HOST=sso.example.com       Override host list with a single hostname.
  VPN_BOOTSTRAP_HOSTS="vpn.example.com sso.example.com"
  VPN_PUBLIC_DNS_SERVERS="1.1.1.1 9.9.9.9"
USAGE
}

mode="${1:-}"
if [[ -z "$mode" ]]; then
  usage
  exit 2
fi

physical_default_gateway() {
  netstat -rn -f inet \
    | awk '$1 == "default" && $NF == "en0" && $2 ~ /^[0-9.]+$/ { print $2; exit }'
}

resolve_host_ips() {
  local host="$1"
  local dns

  {
    for dns in "${PUBLIC_DNS_SERVERS[@]}"; do
      dig @"$dns" +time=2 +tries=1 +short "$host" A 2>/dev/null \
        | awk '/^[0-9.]+$/ {print}' || true
    done

    dig +time=2 +tries=1 +short "$host" A 2>/dev/null \
      | awk '/^[0-9.]+$/ {print}' || true
  } | sort -u
}

route_host_via_gateway() {
  local ip="$1"

  route -n delete -host "$ip" >/dev/null 2>&1 || true
  route -n add -host "$ip" "$gateway"
}

install_dns_server_routes() {
  local dns

  for dns in "${PUBLIC_DNS_SERVERS[@]}"; do
    [[ "$dns" =~ ^[0-9.]+$ ]] || continue
    [[ "$dns" == "$gateway" ]] && continue
    route_host_via_gateway "$dns"
  done
}

remove_dns_server_routes() {
  local dns

  for dns in "${PUBLIC_DNS_SERVERS[@]}"; do
    [[ "$dns" =~ ^[0-9.]+$ ]] || continue
    [[ "$dns" == "$gateway" ]] && continue
    route -n delete -host "$dns" "$gateway" 2>/dev/null \
      || route -n delete -host "$dns" 2>/dev/null \
      || true
  done
}

install_bootstrap_resolvers() {
  mkdir -p /etc/resolver

  for host in "${BOOTSTRAP_HOSTS[@]}"; do
    {
      for dns in "${PUBLIC_DNS_SERVERS[@]}"; do
        echo "nameserver ${dns}"
      done
      echo "timeout 2"
    } > "/etc/resolver/${host}"
  done

  dscacheutil -flushcache || true
  killall -HUP mDNSResponder 2>/dev/null || true
}

remove_bootstrap_resolvers() {
  for host in "${BOOTSTRAP_HOSTS[@]}"; do
    rm -f "/etc/resolver/${host}"
  done

  dscacheutil -flushcache || true
  killall -HUP mDNSResponder 2>/dev/null || true
}

gateway="$(physical_default_gateway)"
if [[ -z "$gateway" ]]; then
  echo "Could not find a non-utun default gateway." >&2
  exit 1
fi

status() {
  echo "Physical gateway: ${gateway}"
  echo
  for host in "${BOOTSTRAP_HOSTS[@]}"; do
    echo "Host: ${host}"
    local ips
    ips="$(resolve_host_ips "$host")"
    if [[ -z "$ips" ]]; then
      echo "  unresolved"
      continue
    fi
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      echo "  IP: ${ip}"
      route -n get "$ip" || true
    done <<< "$ips"
    echo
  done

  echo "Bootstrap resolvers:"
  for host in "${BOOTSTRAP_HOSTS[@]}"; do
    echo "--- /etc/resolver/${host}"
    if [[ -f "/etc/resolver/${host}" ]]; then
      cat "/etc/resolver/${host}"
    else
      echo "missing"
    fi
  done
}

case "$mode" in
  install)
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "Run install with sudo." >&2
      exit 1
    fi
    install_dns_server_routes
    for host in "${BOOTSTRAP_HOSTS[@]}"; do
      ips="$(resolve_host_ips "$host")"
      if [[ -z "$ips" ]]; then
        echo "Could not resolve ${host}" >&2
        continue
      fi
      while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        route_host_via_gateway "$ip"
      done <<< "$ips"
    done
    install_bootstrap_resolvers
    status
    ;;
  remove)
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "Run remove with sudo." >&2
      exit 1
    fi
    install_dns_server_routes
    for host in "${BOOTSTRAP_HOSTS[@]}"; do
      ips="$(resolve_host_ips "$host")"
      while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        route -n delete -host "$ip" "$gateway" 2>/dev/null \
          || route -n delete -host "$ip" 2>/dev/null \
          || true
      done <<< "$ips"
    done
    remove_dns_server_routes
    remove_bootstrap_resolvers
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
