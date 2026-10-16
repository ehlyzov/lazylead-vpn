#!/usr/bin/env python3
"""Build an IPv4 route snapshot from official Yandex Cloud sources.

Run as the normal user. This downloads public metadata and never changes routes.
"""
import argparse
import concurrent.futures
import datetime
import ipaddress
import json
import pathlib
import re
import subprocess

BASE = "https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/"
SOURCES = [BASE + path for path in (
    "public-ip/ru/vpc-ipv4.md", "public-ip/ru/baremetal.md",
    "sws-ips.md", "smartcaptcha-ips.md",
)]
CDN = "https://tech.cdn.yandex.net/prefixes/yc.json"
ENDPOINTS = "https://api.cloud.yandex.net/endpoints"
WEB_HOSTS = {
    "yandex.cloud", "console.yandex.cloud", "auth.yandex.cloud",
    "api.cloud.yandex.net", "storage.yandexcloud.net", "cr.yandex",
    "container-registry.cloud.yandex.net", "registry.yandexcloud.net",
}


def fetch(url, interface):
    command = ["/usr/bin/curl", "-fsSL", "--connect-timeout", "5", "--max-time", "25"]
    if interface:
        command += ["--interface", interface]
    return subprocess.check_output(command + [url], text=True)


def ipv4_network(value):
    network = ipaddress.ip_network(value, strict=True)
    if network.version != 4 or not network.is_global or network.prefixlen < 8:
        raise ValueError("Not an acceptable public IPv4 prefix: " + value)
    return network


def resolve(host):
    text = subprocess.check_output(
        ["/usr/bin/dig", "+time=2", "+tries=1", "+short", "A", host], text=True, timeout=6
    )
    addresses = []
    for line in text.splitlines():
        try:
            address = ipaddress.IPv4Address(line)
        except ValueError:
            continue
        if address.is_global:
            addresses.append(str(address))
    return host, addresses


def collect(interface):
    networks = set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        contents = list(pool.map(lambda url: fetch(url, interface), SOURCES + [CDN, ENDPOINTS]))
    for content in contents[:len(SOURCES)]:
        matches = re.findall(r"`(\d+(?:\.\d+){3}(?:/\d+)?)`", content)
        if not matches:
            raise ValueError("No IPv4 ranges found in an official source")
        networks.update(ipv4_network(value) for value in matches)
    for value in json.loads(contents[-2])["prefixes"]:
        if ":" not in value:
            networks.add(ipv4_network(value))
    endpoints = json.loads(contents[-1])["endpoints"]
    if not endpoints:
        raise ValueError("Empty API endpoint directory")
    hosts = WEB_HOSTS | {entry["address"].rsplit(":", 1)[0] for entry in endpoints}
    if any(not re.fullmatch(r"[a-zA-Z0-9.-]+", host) for host in hosts):
        raise ValueError("Invalid endpoint hostname")
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        resolved = dict(pool.map(resolve, sorted(hosts)))
    unresolved = [host for host, addresses in resolved.items() if not addresses]
    for addresses in resolved.values():
        networks.update(ipv4_network(address) for address in addresses)
    # Keep endpoint /32s even inside provider ranges to override stale host routes.
    ordered = sorted(networks, key=lambda value: (int(value.network_address), value.prefixlen))
    return ordered, {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "sources": SOURCES + [CDN, ENDPOINTS],
        "api_service_count": len(endpoints), "resolved_hosts": resolved,
        "unresolved_hosts": unresolved, "ipv4_prefix_count": len(ordered),
        "scope": "Published IPv4 networks, CDN, API endpoints, console/auth/storage hosts. IPv6 is not configured.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--interface", default="en0")
    args = parser.parse_args()
    routes, report = collect(args.interface)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "yandex-cloud-ipv4.txt").write_text("".join(str(route) + "\n" for route in routes))
    (args.output / "yandex-cloud-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Collected {len(routes)} IPv4 prefixes; {report['api_service_count']} API services")
    if report["unresolved_hosts"]:
        print("Hosts without an A record: " + ", ".join(report["unresolved_hosts"]))
