# Troubleshooting and removing rules

[Back to README](../README.md) | [Русский](ru/troubleshooting.md)

Replace `lazylead-vpn` with your VM name in all commands.

## A selected site is unreachable

```bash
limactl list
limactl shell --workdir / lazylead-vpn ip -4 route show default
ping -c 1 192.168.64.2
route -n get 192.168.64.2
scutil --dns
```

The VM must be running, its default route must use only `direct0`, and
`192.168.64.2` must be directly reachable through the Mac's bridge. A route to
`192.168.64.2` through `192.168.64.2` is an invalid recursive route. When
upgrading from an old experimental version, run
`sudo ./scripts/install_direct_routes.sh`: the updated helper removes its own
old scoped `/1` routes/PF rule and restores the ARP path if necessary.

Check system DNS and address routes without bypassing the resolver with `dig`:

```bash
python3 - <<'PY'
import socket, subprocess
for name in ('yandex.ru', 'президент.рф', 'api.cloud.yandex.net'):
    for address in sorted({row[4][0] for row in socket.getaddrinfo(name, 443, socket.AF_INET)}):
        print(name, address)
        print(subprocess.check_output(['/sbin/route', '-n', 'get', address], text=True))
PY
curl -4 --connect-timeout 5 --max-time 15 https://api.cloud.yandex.net/endpoints
```

Expect `gateway: 192.168.64.2` for selected addresses. `dig` without an explicit
server does not test macOS `/etc/resolver` rules. To query the service directly,
use `dig @127.0.0.1 -p 1054 yandex.ru A`.

Mac logs:

- `~/Library/Logs/Lazylead VPN/` — app;
- `/var/log/lazylead-direct/gov-dns.stderr.log` — DNS-to-route;
- `/var/log/lazylead-direct/routes.stderr.log` — Yandex Cloud routes;
- `/var/log/lazylead-direct/stderr.log` — socket_vmnet.

Inside the VM:

```bash
limactl shell --workdir / lazylead-vpn systemctl status lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn resolvectl status direct0
limactl shell --workdir / lazylead-vpn curl -4 --max-time 15 https://api.cloud.yandex.net/endpoints
```

If the site works inside the VM but not from the Mac, check the Mac→VM path
and host routes. If addresses have changed, regenerate and reinstall the
Yandex Cloud snapshot. If Terminal works but the browser does not, check DoH
and restart the browser. Do not keep rerunning installers after the same error;
record the message and inspect the relevant component.

## Sites fail after restarting or rebuilding Lima

Compare `route -n get 192.168.64.2` with `route -n get <site IPv4>`.
Both should use the current Lima bridge. macOS can preserve a host route's
Lima gateway while rebinding it to `en0` when the bridge disappears.
The DNS helper repairs its own exact host routes when their interface differs
from the gateway's current bridge. It leaves unowned routes and covering prefixes
unchanged and refuses to create routes when the gateway has no local bridge.

Update the DNS helper once after pulling the fix:

```bash
sudo ./scripts/install_gov_routes.sh
```

## Transmission Web UI is unavailable

```bash
limactl shell --workdir / lazylead-vpn systemctl status lazylead-transmission.service
limactl shell --workdir / lazylead-vpn findmnt /mnt/mac-downloads
curl --max-time 5 http://127.0.0.1:9092/transmission/web/
```

You need a running VM, a writable virtiofs Downloads mount, and the port forward
`127.0.0.1:9092 → guest 127.0.0.1:9091`. Changing mounts requires restarting the
VM. Do not start a second daemon over an existing queue.

## Removing rules

While the VM is running, remove DNS rules first, then Yandex Cloud prefixes:

```bash
sudo ./scripts/install_gov_routes.sh remove
sudo ./scripts/install_direct_routes.sh remove
limactl stop lazylead-vpn
```

Only owned resolver files and recorded routes are removed. Helpers should not
remove a route that another application has changed. The VM, Transmission
queue, and downloaded files remain. Remove the app from `/Applications` as usual.

To remove the socket_vmnet service as well, after stopping the VM:

```bash
sudo launchctl bootout system/io.lazylead.direct-network
sudo rm /Library/LaunchDaemons/io.lazylead.direct-network.plist
```

To roll back the app, close the current version and restore the saved
`build/Lazylead VPN.before-<timestamp>.app` to `/Applications/Lazylead VPN.app`.
