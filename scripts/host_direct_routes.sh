#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

VM_IP=192.168.64.2
HOST_IP=192.168.64.1
ANCHOR=com.apple/lazylead-direct
DATA=/opt/lazylead-direct/yandex-cloud-ipv4.txt
STATE=/private/var/run/lazylead-direct-routes

[[ "$(id -u)" == 0 ]] || { echo "Run with sudo." >&2; exit 1; }
mkdir -p "$STATE"
chmod 0755 "$STATE"

gateway_for() {
  route -n get "$1" 2>/dev/null | awk '$1 == "gateway:" {print $2; exit}'
}

cleanup_legacy_binding() {
  if [[ -f "$STATE/scoped-bridge" ]]; then
    local old_bridge
    old_bridge="$(cat "$STATE/scoped-bridge")"
    if [[ "$old_bridge" =~ ^bridge[0-9]+$ ]]; then
      for prefix in 0.0.0.0/1 128.0.0.0/1; do
        route -n delete -net -ifscope "$old_bridge" "$prefix" "$VM_IP" >/dev/null 2>&1 || true
      done
    fi
    rm -f "$STATE/scoped-bridge"
  fi
  if [[ -f "$STATE/applied.pf" ]]; then
    pfctl -a "$ANCHOR" -F rules
    rm -f "$STATE/applied.pf"
  fi
  if [[ -f "$STATE/pf-token" ]]; then
    pfctl -X "$(cat "$STATE/pf-token")"
    rm -f "$STATE/pf-token"
  fi
}

case "${1:-}" in
  install)
    # Serialise the launchd timer and manual installations.
    mkdir "$STATE/lock" 2>/dev/null || exit 0
    trap 'rmdir "$STATE/lock"' EXIT
    bridge="$(ifconfig -a | awk -v ip="$HOST_IP" '
      /^[[:alnum:]]/ { interface=$1; sub(/:$/, "", interface) }
      $1 == "inet" && $2 == ip && interface ~ /^bridge[0-9]+$/ {print interface; exit}
    ')"
    [[ "$bridge" =~ ^bridge[0-9]+$ ]] || { echo "Lima host network is not available." >&2; exit 1; }
    ifconfig "$bridge" | awk -v ip="$HOST_IP" '$1 == "inet" && $2 == ip {found=1} END {exit !found}'
    # Remove the obsolete native-Transmission source-binding experiment.
    cleanup_legacy_binding
    link_gateway="$(gateway_for "$VM_IP")"
    if [[ "$link_gateway" == "$VM_IP" || -z "$link_gateway" ]] || ! ping -n -c 1 -W 1000 "$VM_IP" >/dev/null 2>&1; then
      # Restore a direct ARP path if VZ's connected route disappeared.
      route -n add -host "$VM_IP" -interface "$bridge" >/dev/null
      echo "$bridge" > "$STATE/vm-link-route"
    fi
    ping -n -c 1 -W 1000 "$VM_IP" >/dev/null
    test -s "$DATA"

    touch "$STATE/installed-prefixes"
    count=0
    while IFS= read -r prefix; do
      [[ -n "$prefix" ]] || continue
      [[ "$prefix" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || exit 1
      address="${prefix%/*}"
      if [[ "$(gateway_for "$address")" != "$VM_IP" ]]; then
        route -n add -net "$prefix" "$VM_IP" >/dev/null || {
          echo "Could not add $prefix; existing conflicting routes were left intact." >&2
          exit 1
        }
        grep -Fxq "$prefix" "$STATE/installed-prefixes" || echo "$prefix" >> "$STATE/installed-prefixes"
      fi
      count=$((count + 1))
    done < "$DATA"
    {
      echo "updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "bridge=$bridge"
      echo "gateway=$VM_IP"
      echo "yandex_ipv4_prefixes=$count"
      echo "routing_mode=destination-prefixes"
    } > "$STATE/status.txt.new"
    mv "$STATE/status.txt.new" "$STATE/status.txt"
    ;;
  remove)
    cleanup_legacy_binding
    if [[ -f "$STATE/installed-prefixes" ]]; then
      while IFS= read -r prefix; do
        if [[ "$(gateway_for "${prefix%/*}")" == "$VM_IP" ]]; then
          route -n delete -net "$prefix" "$VM_IP" >/dev/null 2>&1 || true
        fi
      done < "$STATE/installed-prefixes"
      rm -f "$STATE/installed-prefixes"
    fi
    if [[ -f "$STATE/vm-link-route" ]]; then
      bridge="$(cat "$STATE/vm-link-route")"
      [[ ! "$bridge" =~ ^bridge[0-9]+$ ]] || route -n delete -host "$VM_IP" -interface "$bridge" >/dev/null 2>&1 || true
      rm -f "$STATE/vm-link-route"
    fi
    rm -f "$STATE/status.txt"
    ;;
  status)
    cat "$STATE/status.txt"
    ;;
  *) echo "Usage: $0 install|remove|status" >&2; exit 2 ;;
esac
