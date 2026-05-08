#!/usr/bin/env bash
set -u

usage() {
  cat <<'USAGE'
Usage:
  ./vpn_probe.sh --label checkpoint host1.example.com host2.example.com
  ./vpn_probe.sh --label secondary host1.example.com

The script is read-only. It writes a timestamped report under ./vpn-probe-reports.

Recommended flow:
  1. Disconnect all VPNs, then run: ./vpn_probe.sh --label baseline host.example.com
  2. Connect Check Point only, then run: ./vpn_probe.sh --label checkpoint host.example.com
  3. Connect the other VPN only, then run: ./vpn_probe.sh --label secondary host.example.com
  4. If both can stay connected for a moment, run: ./vpn_probe.sh --label both host.example.com
USAGE
}

label="snapshot"
hosts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label|-l)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for $1" >&2
        exit 2
      fi
      label="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      hosts+=("$1")
      shift
      ;;
  esac
done

if [[ ${#hosts[@]} -eq 0 ]]; then
  hosts=("example.com")
fi

safe_label="$(printf '%s' "$label" | tr -c '[:alnum:]_.-' '_')"
timestamp="$(date '+%Y%m%d-%H%M%S')"
out_dir="./vpn-probe-reports"
out_file="${out_dir}/${timestamp}-${safe_label}.txt"
mkdir -p "$out_dir"

run() {
  local title="$1"
  shift
  {
    printf '\n\n### %s\n' "$title"
    printf '$'
    printf ' %q' "$@"
    printf '\n'
  } >> "$out_file"

  "$@" >> "$out_file" 2>&1 || {
    local status=$?
    printf '[command exited with status %s]\n' "$status" >> "$out_file"
  }
}

section() {
  printf '\n\n# %s\n' "$1" >> "$out_file"
}

resolve_host() {
  local host="$1"
  section "Host checks: ${host}"

  run "dig A ${host}" dig +time=2 +tries=1 "$host" A
  run "dig AAAA ${host}" dig +time=2 +tries=1 "$host" AAAA
  run "dig CNAME ${host}" dig +time=2 +tries=1 "$host" CNAME
  run "dscacheutil ${host}" dscacheutil -q host -a name "$host"
  run "route get ${host}" route -n get "$host"

  local ips
  ips="$(dig +short +time=2 +tries=1 "$host" A 2>/dev/null | awk '/^[0-9.]+$/ {print}' | sort -u)"
  if [[ -n "$ips" ]]; then
    while IFS= read -r ip; do
      [[ -z "$ip" ]] && continue
      run "route get ${ip}" route -n get "$ip"
      run "ping probe ${ip}" ping -c 2 -W 1000 "$ip"
    done <<< "$ips"
  else
    printf '\nNo IPv4 A records resolved for %s via current DNS.\n' "$host" >> "$out_file"
  fi
}

{
  echo "# VPN probe report"
  echo "Label: ${label}"
  echo "Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ') UTC"
  echo "Local time: $(date)"
  echo "User: $(id -un)"
  echo "Working directory: $(pwd)"
  echo
  echo "Hosts:"
  for host in "${hosts[@]}"; do
    echo "- ${host}"
  done
} > "$out_file"

section "System"
run "macOS version" sw_vers
run "kernel" uname -a
run "current public IP" curl -4 --max-time 4 -s https://ifconfig.me

section "Network state"
run "scutil --nwi" scutil --nwi
run "scutil --dns" scutil --dns
run "network services" networksetup -listallnetworkservices
run "hardware ports" networksetup -listallhardwareports
run "service order" networksetup -listnetworkserviceorder

section "Interfaces"
run "ifconfig" ifconfig
run "utun summary" sh -c "ifconfig | awk '/^[a-z0-9]+:/{iface=\$1; sub(\":\", \"\", iface)} iface ~ /^utun/ || /inet |inet6 |status:|description:|flags=/'"

section "Routes"
run "IPv4 routes" netstat -rn -f inet
run "IPv6 routes" netstat -rn -f inet6
run "default IPv4 route" route -n get default
run "default IPv6 route" route -n get -inet6 default

section "VPN-ish processes"
run "process scan" ps ax -o pid,ppid,user,command
run "network extensions" systemextensionsctl list
run "launch agents scan" sh -c "launchctl list | egrep -i 'checkpoint|check point|vpn|wireguard|openvpn|tunnel|ipsec|ike|utun|network' || true"

section "Packet filter"
run "pf status" pfctl -s info
run "pf anchors" pfctl -s Anchors

for host in "${hosts[@]}"; do
  resolve_host "$host"
done

cat <<EOF
Report written to:
  ${out_file}

Run this once per state: baseline, checkpoint, secondary, and both if possible.
EOF
