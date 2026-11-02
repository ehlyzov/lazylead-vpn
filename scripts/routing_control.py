#!/usr/bin/env python3
"""Narrow administrator actions used by the Network & Routes window."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys
import tempfile
import time

import routing_rules

TARGET = Path('/opt/lazylead-direct/domain-dns')
STATE = Path('/private/var/db/lazylead-domain-dns')
RESOLVERS = Path('/private/etc/resolver')
LABEL = 'system/io.lazylead.gov-dns'


def run(args, timeout=15):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or 'Command failed: ' + args[0])
    return p.stdout


def atomic(path, data, mode=0o644):
    fd, name = tempfile.mkstemp(prefix='.lazylead-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def safe(path):
    for item in [path] + list(path.parents)[:-1]:
        if item.is_symlink():
            raise ValueError('Refusing a symlink: ' + str(item))
        if item.exists():
            st = item.stat()
            if st.st_uid != 0 or st.st_mode & 0o022:
                raise ValueError('Expected a root-owned path without group/other write access: ' + str(item))


def resolver_text(name):
    return ('# Managed by Lazylead ' + name + ' routing\ndomain ' + name +
            '\nnameserver 127.0.0.1\nport 1054\ntimeout 4\nsearch_order 100\n').encode()


def read_current():
    if routing_rules.CONFIG.exists():
        return routing_rules.load()
    # Adopt the rules actually installed on this Mac, including older versions.
    domains = []
    if RESOLVERS.exists():
        for path in RESOLVERS.iterdir():
            if path.is_file() and not path.is_symlink():
                name = path.name
                if ('# Managed by Lazylead ' + name + ' routing') in path.read_text(errors='replace').splitlines():
                    domains.append(routing_rules.domain(name))
    return {'version': 1, 'domains': sorted(domains), 'networks': []}


def reconcile():
    run(['/usr/bin/python3', str(TARGET / 'domain_dns.py'), '--reconcile'], timeout=90)


def change(kind, value, remove):
    value = routing_rules.domain(value) if kind == 'domain' else routing_rules.network(value)
    if not (TARGET / 'vendor/dnslib').is_dir() or not Path('/Library/LaunchDaemons/io.lazylead.gov-dns.plist').is_file():
        raise ValueError('Install Lima Direct routing first; see the installation guide.')
    for path in (TARGET, STATE, RESOLVERS, routing_rules.CONFIG, STATE / 'routes.json', STATE / 'prefixes.json'):
        safe(path)
    STATE.mkdir(mode=0o700, exist_ok=True)
    lockpath = STATE / 'control.lock'
    safe(lockpath)
    with lockpath.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = read_current()
        new = json.loads(json.dumps(old))
        key = 'domains' if kind == 'domain' else 'networks'
        values = set(new[key])
        if remove:
            values.discard(value)
        else:
            values.add(value)
        new[key] = sorted(values)
        if len(new[key]) > 500:
            raise ValueError('At most 500 rules of each type are supported.')
        resolver_paths = [RESOLVERS / name for name in set(old['domains']) | set(new['domains'])]
        for path in resolver_paths:
            safe(path)
            if path.exists() and ('# Managed by Lazylead ' + path.name + ' routing') not in path.read_text().splitlines():
                raise ValueError('An existing DNS resolver belongs to another configuration: ' + path.name)
        resolver_backup = {p: p.read_bytes() if p.exists() else None for p in resolver_paths}
        ledger_backup = {}
        for name in ('routes.json', 'prefixes.json'):
            p = STATE / name
            ledger_backup[p] = json.loads(p.read_text()) if p.exists() else {}
        # Stop the old process before upgrading its code or reconciling its ledger.
        run(['/bin/launchctl', 'bootout', LABEL])
        try:
            source = Path(__file__).resolve().parent
            for name in ('domain_dns.py', 'routing_rules.py'):
                destination = TARGET / name
                safe(destination)
                content = (source / name).read_bytes()
                compile(content, name, 'exec')
                atomic(destination, content, 0o755 if name.endswith('dns.py') else 0o644)
            atomic(routing_rules.CONFIG, (json.dumps(new, indent=2) + '\n').encode())
            reconcile()
            for path in resolver_paths:
                if path.name in new['domains']:
                    atomic(path, resolver_text(path.name))
                elif path.exists():
                    path.unlink()
        except Exception:
            atomic(routing_rules.CONFIG, (json.dumps(old, indent=2) + '\n').encode())
            for path, previous in resolver_backup.items():
                if previous is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic(path, previous)
            # Keep new owned entries so reconciliation can undo partially added routes.
            for path, previous in ledger_backup.items():
                current = json.loads(path.read_text()) if path.exists() else {}
                current.update(previous)
                atomic(path, (json.dumps(current) + '\n').encode(), 0o600)
            reconcile()
            raise
        finally:
            run(['/bin/launchctl', 'bootstrap', 'system', '/Library/LaunchDaemons/io.lazylead.gov-dns.plist'])
            run(['/usr/bin/dscacheutil', '-flushcache'])
            run(['/usr/bin/killall', '-HUP', 'mDNSResponder'])
        print('Routing rule removed.' if remove else 'Routing rule added.')


def repair_network():
    service = 'system/io.lazylead.direct-network'
    ready = Path('/private/var/run/lazylead-direct.sock')
    before = ready.stat().st_mtime_ns if ready.exists() else 0
    run(['/bin/launchctl', 'kickstart', '-k', service])
    for _ in range(80):
        if ready.exists() and stat.S_ISSOCK(ready.stat().st_mode) and ready.stat().st_mtime_ns != before:
            with socket.socket(socket.AF_UNIX) as connection:
                connection.settimeout(1)
                connection.connect(str(ready))
            print('Direct network service is ready.')
            return
        time.sleep(0.25)
    raise RuntimeError('The network bridge did not become ready within 20 seconds. Lima remains stopped; see Settings → Logs.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['status', 'repair-network', 'add', 'remove'])
    parser.add_argument('kind', nargs='?', choices=['domain', 'network'])
    parser.add_argument('value', nargs='?')
    args = parser.parse_args()
    if args.action == 'status':
        print(json.dumps(read_current()))
        return
    if os.geteuid() != 0:
        raise ValueError('Administrator authorization is required.')
    if args.action == 'repair-network':
        repair_network()
    else:
        if not args.kind or not args.value:
            parser.error('A rule type and value are required.')
        change(args.kind, args.value, args.action == 'remove')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
