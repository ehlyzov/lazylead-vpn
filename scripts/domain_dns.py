#!/usr/bin/env python3
"""Resolve selected domains through Lima, adding IPv4 routes before DNS answers."""
import argparse
import ipaddress
import json
import logging
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parent / 'vendor'))
from dnslib import DNSRecord, QTYPE, RCODE, HTTPS, RDMAP
from dnslib.server import BaseResolver, DNSServer, DNSLogger

RDMAP['SVCB'] = HTTPS
GATEWAY = '192.168.64.2'
RETENTION = 86400
DOMAINS = ('ru', 'xn--p1ai', 'tbank-online.com', 'codenrock.com')  # .рф in DNS/IDNA form.


def in_zone(name):
    try:
        name = str(name).rstrip('.').encode('idna').decode('ascii').lower()
    except UnicodeError:
        return False
    return any(name == domain or name.endswith('.' + domain) for domain in DOMAINS)


class Routes:
    def __init__(self, state, dry_run=False):
        self.path = Path(state)
        self.dry_run = dry_run
        self.lock = threading.RLock()
        self.entries = json.loads(self.path.read_text()) if self.path.exists() else {}

    def command(self, *args):
        return subprocess.run(['/sbin/route', '-n'] + list(args),
                              capture_output=True, text=True, timeout=5)

    def lookup(self, address):
        output = self.command('get', address).stdout
        return dict(re.findall(r'^\s*(destination|gateway|interface|flags):\s*(.+)$', output, re.M))

    def save(self):
        if self.dry_run:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix('.new')
        temporary.write_text(json.dumps(self.entries, indent=2) + '\n')
        temporary.chmod(0o600)
        temporary.replace(self.path)

    def install(self, address):
        if self.dry_run:
            return False
        route = self.lookup(address)
        if route.get('gateway') == GATEWAY:
            return False
        # Discard only a kernel-generated VPN host cache entry, never a user's
        # static route. A fresh unscoped host route takes precedence afterward.
        flags = route.get('flags', '')
        interface = route.get('interface', '')
        if 'WASCLONED' in flags and 'HOST' in flags and 'IFSCOPE' in flags and re.fullmatch(r'utun\d+', interface):
            self.command('delete', '-host', '-ifscope', interface, address)
        result = self.command('add', '-host', address, GATEWAY)
        if self.lookup(address).get('gateway') != GATEWAY:
            raise RuntimeError('Could not route ' + address + ' through Lima')
        return result.returncode == 0 and 'File exists' not in result.stderr

    def ensure(self, addresses, retention=RETENTION):
        with self.lock:
            for address in sorted(set(addresses)):
                parsed = ipaddress.ip_address(address)
                if parsed.version != 4 or not parsed.is_global or parsed.is_multicast:
                    raise ValueError('Refusing a non-public IPv4 route')
                previous = self.entries.get(address, {})
                created = self.install(address)
                self.entries[address] = {
                    'expires': max(time.time() + retention, previous.get('expires', 0)),
                    'owned': created or previous.get('owned', False),
                }
            self.save()

    def remove_entry(self, address, entry):
        if not entry.get('owned') or self.dry_run:
            return
        route = self.lookup(address)
        if route.get('gateway') == GATEWAY and 'HOST' in route.get('flags', '') and route.get('destination') == address:
            self.command('delete', '-host', address, GATEWAY)

    def maintain(self, remove_all=False):
        with self.lock:
            for address, entry in list(self.entries.items()):
                # Validate persisted input before passing it to route(8).
                if str(ipaddress.IPv4Address(address)) != address:
                    raise ValueError('Invalid persisted address')
                if remove_all or entry['expires'] < time.time():
                    self.remove_entry(address, entry)
                    del self.entries[address]
                else:
                    entry['owned'] = self.install(address) or entry['owned']
            self.save()


class DomainResolver(BaseResolver):
    def __init__(self, routes):
        self.routes = routes

    def upstream(self, request):
        response = DNSRecord.parse(request.send(GATEWAY, 1053, timeout=3))
        if response.header.tc:
            response = DNSRecord.parse(request.send(GATEWAY, 1053, tcp=True, timeout=3))
        if response.header.id != request.header.id or response.q != request.q:
            raise ValueError('Mismatched upstream DNS response')
        return response

    def resolve(self, request, handler):
        failure = request.reply()
        failure.header.aa = 0
        failure.header.ra = 1
        if len(request.questions) != 1 or not in_zone(request.q.qname) or request.q.qclass != 1:
            failure.header.rcode = RCODE.REFUSED
            return failure
        # The Lima forwarding setup is IPv4-only. Do not offer a parallel
        # IPv6 connection that would use the Mac's ordinary route.
        if request.q.qtype == QTYPE.AAAA:
            return failure
        try:
            response = self.upstream(request)
            if response.header.rcode != RCODE.NOERROR:
                return response
            if request.q.qtype == QTYPE.A:
                seen = {str(request.q.qname).lower()}
                for _ in range(8):
                    if any(rr.rtype == QTYPE.A for rr in response.rr):
                        break
                    aliases = [rr for rr in response.rr if rr.rtype == QTYPE.CNAME]
                    if not aliases:
                        break
                    target = str(aliases[-1].rdata)
                    if target.lower() in seen:
                        raise ValueError('CNAME loop')
                    seen.add(target.lower())
                    more = self.upstream(DNSRecord.question(target, 'A'))
                    if more.header.rcode != RCODE.NOERROR:
                        raise ValueError('CNAME target resolution failed')
                    response.rr.extend(more.rr)
                    if not more.rr:
                        break
                else:
                    raise ValueError('CNAME chain too long')

            addresses = set()
            changed = False
            for section in (response.rr, response.auth, response.ar):
                for rr in list(section):
                    if rr.rtype == QTYPE.A:
                        addresses.add(str(rr.rdata))
                    elif rr.rtype == QTYPE.AAAA:
                        section.remove(rr)
                        changed = True
                    elif rr.rtype in (64, 65):
                        params = []
                        for key, value in rr.rdata.params:
                            if key == 4:
                                if len(value) % 4:
                                    raise ValueError('Invalid ipv4hint')
                                addresses.update(str(ipaddress.IPv4Address(bytes(value[i:i + 4])))
                                                 for i in range(0, len(value), 4))
                            if key == 0 and any(value[i:i + 2] == b'\x00\x06' for i in range(0, len(value), 2)):
                                raise ValueError('Mandatory IPv6 service is unsupported')
                            if key == 6:
                                changed = True
                            else:
                                params.append((key, value))
                        # Preserve ECH and all unrelated service parameters.
                        rr.rdata.params = params
                        target = b'.'.join(bytes(label) for label in rr.rdata.target).decode('ascii')
                        if target:
                            target_reply = self.upstream(DNSRecord.question(target, 'A'))
                            addresses.update(str(record.rdata) for record in target_reply.rr if record.rtype == QTYPE.A)
            if changed:
                response.header.ad = 0
                for section in (response.rr, response.auth, response.ar):
                    section[:] = [rr for rr in section if not (rr.rtype == QTYPE.RRSIG and rr.rdata.covered in (28, 64, 65))]
            ttl = max([rr.ttl for rr in response.rr + response.ar] + [0])
            self.routes.ensure(addresses, retention=RETENTION + ttl)
            return response
        except Exception as error:
            logging.warning('Lima domain DNS request failed: %s', error)
            failure.header.rcode = RCODE.SERVFAIL
            return failure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=1054)
    parser.add_argument('--state', default='/var/db/lazylead-domain-dns/routes.json')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--remove-routes', action='store_true')
    args = parser.parse_args()
    if not args.dry_run and os.geteuid() != 0:
        parser.error('root is required to manage host routes')
    routes = Routes(args.state, args.dry_run)
    if args.remove_routes:
        routes.maintain(remove_all=True)
        return
    resolver = DomainResolver(routes)
    logger = DNSLogger(log='error', prefix=False)
    servers = [DNSServer(resolver, address='127.0.0.1', port=args.port,
                         tcp=tcp, logger=logger) for tcp in (False, True)]
    for server in servers:
        server.start_thread()
    logging.warning('Lima resolver for %s ready on 127.0.0.1:%d (dry_run=%s)',
                    ', '.join(DOMAINS), args.port, args.dry_run)
    while all(server.isAlive() for server in servers):
        try:
            routes.maintain()
        except Exception as error:
            logging.warning('Route refresh failed: %s', error)
        time.sleep(30)


if __name__ == '__main__':
    main()
