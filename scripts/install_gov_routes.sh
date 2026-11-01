#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET=/opt/lazylead-direct/domain-dns
LABEL=io.lazylead.gov-dns
PLIST="/Library/LaunchDaemons/$LABEL.plist"
DOMAINS=(ru xn--p1ai tbank-online.com codenrock.com hideogenius.com ppc.ipchanger.live)
LEGACY_DOMAINS=(gov.ru gosuslugi.ru)
WHEEL="$ROOT_DIR/build/domain-routing/dnslib-0.9.26-py3-none-any.whl"
[[ "$(id -u)" == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }

if [[ "${1:-}" == remove ]]; then
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  python3 "$TARGET/domain_dns.py" --remove-routes
  for domain in "${DOMAINS[@]}" "${LEGACY_DOMAINS[@]}"; do
    resolver="/etc/resolver/$domain"
    if [[ -f "$resolver" ]] && grep -Fxq "# Managed by Lazylead $domain routing" "$resolver"; then
      rm "$resolver"
    fi
  done
  rm -f "$PLIST"
  dscacheutil -flushcache
  killall -HUP mDNSResponder
  echo 'Removed .ru, .рф, tbank-online.com, codenrock.com, hideogenius.com and ppc.ipchanger.live resolvers and their owned routes.'
  exit 0
fi
[[ $# == 0 ]] || exit 2
for directory in /opt /opt/lazylead-direct "$TARGET" /etc/resolver; do
  [[ ! -L "$directory" ]] || { echo "Refusing symlink: $directory" >&2; exit 1; }
  if [[ -e "$directory" ]]; then
    [[ "$(stat -f %u "$directory")" == 0 ]] || exit 1
    permissions="$(stat -f %Lp "$directory")"
    (( (8#$permissions & 0022) == 0 )) || exit 1
  fi
done
for domain in "${DOMAINS[@]}"; do
  resolver="/etc/resolver/$domain"
  [[ ! -L "$resolver" ]] || exit 1
  if [[ -e "$resolver" ]] && ! grep -Fxq "# Managed by Lazylead $domain routing" "$resolver"; then
    echo "An existing $domain resolver belongs to another configuration; leaving it intact." >&2
    exit 1
  fi
done
[[ "$(shasum -a 256 "$WHEEL" | awk '{print $1}')" == e68719e633d761747c7e91bd241019ef5a2b61a63f56025939e144c841a70e0d ]]

temporary_dir="$(mktemp -d /private/tmp/lazylead-gov.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
cp "$ROOT_DIR/scripts/domain_dns.py" "$temporary_dir/domain_dns.py"
python3 - "$WHEEL" "$temporary_dir" <<'PY'
from pathlib import Path
import sys
import zipfile
source = Path(sys.argv[2]) / 'domain_dns.py'
compile(source.read_text(), str(source), 'exec')
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(Path(sys.argv[2]) / 'vendor')
PY
# Verify the Lima resolver before modifying host DNS configuration.
PYTHONPATH="$temporary_dir/vendor" python3 - <<'PY'
from dnslib import DNSRecord, QTYPE, RCODE
for host in ('gov.ru', 'gosuslugi.ru', 'yandex.ru', 'президент.рф', 'tbank-online.com', 'codenrock.com', 'play.hideogenius.com', 'ppc.ipchanger.live'):
    r = DNSRecord.parse(DNSRecord.question(host).send('192.168.64.2', 1053, timeout=3))
    assert r.header.rcode == RCODE.NOERROR and any(x.rtype == QTYPE.A for x in r.rr), 'Lima DNS unavailable for ' + host
print('Lima upstream DNS: OK')
PY

launchctl bootout "system/$LABEL" 2>/dev/null || true
install -d -o root -g wheel -m 0755 "$TARGET" "$TARGET/vendor" /etc/resolver /var/log/lazylead-direct
install -d -o root -g wheel -m 0700 /var/db/lazylead-domain-dns
install -o root -g wheel -m 0755 "$temporary_dir/domain_dns.py" "$TARGET/domain_dns.py"
cp -R "$temporary_dir/vendor/dnslib" "$TARGET/vendor/"
cp -R "$temporary_dir/vendor/dnslib-0.9.26.dist-info" "$TARGET/vendor/"
chown -R root:wheel "$TARGET/vendor"
chmod -R go-w "$TARGET/vendor"
python3 - "$PLIST" "$TARGET" "$LABEL" <<'PY'
import plistlib
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = {
    'Label': sys.argv[3],
    'ProgramArguments': ['/usr/bin/python3', sys.argv[2] + '/domain_dns.py'],
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 10,
    'UserName': 'root',
    'StandardOutPath': '/var/log/lazylead-direct/gov-dns.stdout.log',
    'StandardErrorPath': '/var/log/lazylead-direct/gov-dns.stderr.log',
}
path.write_bytes(plistlib.dumps(data))
path.chmod(0o644)
PY
plutil -lint "$PLIST"
launchctl bootstrap system "$PLIST"
PYTHONPATH="$TARGET/vendor" python3 - <<'PY'
import time
import subprocess
from dnslib import DNSRecord, QTYPE, RCODE
for attempt in range(10):
    try:
        for host in ('gov.ru', 'gosuslugi.ru', 'yandex.ru', 'президент.рф', 'tbank-online.com', 'codenrock.com', 'play.hideogenius.com', 'ppc.ipchanger.live'):
            answer = DNSRecord.parse(DNSRecord.question(host).send('127.0.0.1', 1054, timeout=5))
            assert answer.header.rcode == RCODE.NOERROR
            addresses = [str(rr.rdata) for rr in answer.rr if rr.rtype == QTYPE.A]
            assert addresses
            for address in addresses:
                route = subprocess.check_output(['/sbin/route', '-n', 'get', address], text=True)
                assert 'gateway: 192.168.64.2' in route
        print('DNS answer and routes through Lima: OK')
        break
    except (OSError, AssertionError):
        if attempt == 9:
            raise SystemExit('DNS route check failed. Resolver file was not changed. See /var/log/lazylead-direct/gov-dns.stderr.log')
        time.sleep(0.3)
PY
for domain in "${DOMAINS[@]}"; do
  resolver="/etc/resolver/$domain"
  cat > "$resolver" <<EOF
# Managed by Lazylead $domain routing
domain $domain
nameserver 127.0.0.1
port 1054
timeout 4
search_order 100
EOF
  chmod 0644 "$resolver"
done
# More specific files from earlier installations now belong to these TLD rules.
for domain in "${LEGACY_DOMAINS[@]}"; do
  resolver="/etc/resolver/$domain"
  if [[ -f "$resolver" && ! -L "$resolver" ]] && grep -Fxq "# Managed by Lazylead $domain routing" "$resolver"; then
    rm "$resolver"
  fi
done
dscacheutil -flushcache
killall -HUP mDNSResponder
python3 - <<'PY'
import socket
import subprocess
for host in ('gov.ru', 'government.gov.ru', 'gosuslugi.ru', 'esia.gosuslugi.ru',
             'yandex.ru', 'президент.рф', 'tbank-online.com', 'codenrock.com', 'play.hideogenius.com', 'ppc.ipchanger.live'):
    addresses = {row[4][0] for row in socket.getaddrinfo(host, 443, socket.AF_INET)}
    assert addresses, 'No IPv4 addresses for ' + host
    for address in addresses:
        route = subprocess.check_output(['/sbin/route', '-n', 'get', address], text=True)
        assert 'gateway: 192.168.64.2' in route, 'System DNS route check failed for ' + host
print('VERIFIED: .ru, .рф, tbank-online.com, codenrock.com, hideogenius.com and ppc.ipchanger.live with their subdomains use Lima (IPv4).')
PY
