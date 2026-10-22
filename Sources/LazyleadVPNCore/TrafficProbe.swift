/// Read-only guest probe. The gateway is passed as argv, never interpolated into Python.
public enum TrafficProbe {
    public static let python = """
    import ipaddress, json, subprocess, sys
    from pathlib import Path
    gateway = str(ipaddress.IPv4Address(sys.argv[1]))
    routes = json.loads(subprocess.check_output(['ip','-j','-4','route','show','default'], text=True, timeout=3))
    if not routes or any(route.get('dev') != 'direct0' for route in routes):
        raise SystemExit('The only IPv4 default route must use direct0.')
    addresses = json.loads(subprocess.check_output(['ip','-j','-4','address','show'], text=True, timeout=3))
    links = [link['ifname'] for link in addresses if any(a.get('local') == gateway for a in link.get('addr_info', []))]
    if len(links) != 1 or links[0] == 'direct0':
        raise SystemExit('Cannot identify the separate Mac-facing interface.')
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    def reading(name, reverse=False):
        root = Path('/sys/class/net') / name
        rx = int((root/'statistics/rx_bytes').read_text())
        tx = int((root/'statistics/tx_bytes').read_text())
        return {'epoch': boot + ':' + (root/'ifindex').read_text().strip(), 'interface': name,
                'bytes': {'received': tx if reverse else rx, 'sent': rx if reverse else tx}}
    print(json.dumps({'uplink': reading('direct0'), 'macLink': reading(links[0], True)}))
    """
}
