"""Validated, persistent Direct-mode routing preferences shared with the GUI helper."""
import ipaddress
import json
from pathlib import Path
import re

CONFIG = Path('/opt/lazylead-direct/domain-dns/rules.json')
DEFAULT_DOMAINS = ('ru', 'xn--p1ai', 'tbank-online.com', 'codenrock.com',
                   'hideogenius.com', 'ppc.ipchanger.live', 'vkvideo.cloud')
# Do not send local, management, documentation, multicast or default routes to Lima.
RESERVED = tuple(ipaddress.IPv4Network(x) for x in (
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
    '169.254.0.0/16', '172.16.0.0/12', '192.0.0.0/24', '192.0.2.0/24',
    '192.168.0.0/16', '198.18.0.0/15', '198.51.100.0/24', '203.0.113.0/24',
    '224.0.0.0/4', '240.0.0.0/4'))


def domain(value):
    value = value.strip().lower().removeprefix('*.').strip('.')
    try:
        value = value.encode('idna').decode('ascii')
    except UnicodeError:
        raise ValueError('Enter a domain, for example example.com or .ru.')
    if len(value) > 253 or not value or not all(
            re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
            for label in value.split('.')) or value.split('.')[-1].isdigit():
        raise ValueError('Enter a domain without a URL, port, or path.')
    return value


def network(value):
    try:
        net = ipaddress.IPv4Network(value.strip(), strict=False)
    except ValueError:
        raise ValueError('Enter a complete IPv4 address or CIDR, for example 8.8.8.8 or 8.8.8.0/24.')
    if any(net.overlaps(other) for other in RESERVED):
        raise ValueError('Only public IPv4 destinations are supported; local and default routes are protected.')
    return str(net.network_address) if net.prefixlen == 32 else str(net)


def load(path=None):
    path = CONFIG if path is None else path
    if not path.exists():
        return {'version': 1, 'domains': list(DEFAULT_DOMAINS), 'networks': []}
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or data.get('version') != 1:
        raise ValueError('Unsupported routing preferences format.')
    for key in ('domains', 'networks'):
        if not isinstance(data.get(key), list) or len(data[key]) > 500 or not all(isinstance(x, str) for x in data[key]):
            raise ValueError('Invalid routing preferences: ' + key)
    return {'version': 1, 'domains': sorted(set(map(domain, data['domains']))),
            'networks': sorted(set(map(network, data['networks'])))}


def contains(name, domains):
    name = str(name).rstrip('.').encode('idna').decode('ascii').lower()
    return any(name == d or name.endswith('.' + d) for d in domains)
