# Daily use

[Back to README](../README.md) | [Русский](ru/usage.md)

## Starting and stopping

Connect the Mac's primary VPN if needed, open Lazylead VPN, and choose
`Start Lima (Direct)`. If the VM is already running, the command checks its
network. Connected means the VM's default-route check passed; it does not
replace checks of system routes or the availability of individual sites.

`Quit Lazylead VPN` closes only the app. `Stop Lima` shuts down the VM, including
Transmission. DNS rules and selected routes remain on the Mac while the VM
is stopped. To restore normal routing, [remove the rules](troubleshooting.md#removing-rules).

After changing rules, restart the browser to close existing connections and
clear its DNS cache. On the tested Mac, Brave 1.96.60 with Secure DNS set to the
current OS provider respected the system rule. A custom DoH provider may bypass it.

## Seeing what goes through Lima

Choose `Traffic & Routes…` in the menu bar, or use the same button in Settings.
The window opens automatically the first time this feature is launched.
It reads the installed DNS rules, the Yandex Cloud address snapshot, the VM's
status, and the macOS routing table without changing any network settings.

The summary separates configured domains (including all subdomains), Yandex
Cloud ranges, Transmission inside the VM, and the Mac's default route.
The table lists only usable IPv4 routes whose gateway is the configured Lima IP.
`Global` means a route is not limited to one interface; it does not mean all
internet traffic uses Lima. Interface-scoped routes are labeled separately.

Search for an IP, CIDR prefix, or interface. An IP also matches a covering
network, such as `51.250.33.235` matching `51.250.0.0/17`. `Copy routes` copies
the filtered list. `Refresh` reads the current configuration again in the
background; the timestamp shows when it was last collected.

This is a view of configuration and installed routes, not live traffic or an
end-to-end connectivity test. A stopped VM, custom application DNS, more-specific
routes, or a shared destination IP can affect the actual path. Snapshot prefix
counts can exceed the number of matching installed routes because overlapping
prefixes can share a route. Domain names cannot be recovered from an IP-only
routing table, so individual IPs are not presented as verified domain matches.

## Transmission

Open the [Web UI](http://127.0.0.1:9092/transmission/web/) while the VM is running.
Add torrents in the Web UI; completed files appear in `~/Downloads` on the Mac.
The queue and settings persist inside the VM between starts. Do not delete the
VM if you want to keep that state.

Check the service, replacing the VM name with yours:

```bash
limactl shell --workdir / lazylead-vpn systemctl status lazylead-transmission.service
```

## Launching the app at login

```bash
./scripts/install_launch_agent.sh '/Applications/Lazylead VPN.app'
```

This opens the app after login. Click `Start Lima (Direct)` to start the VM;
the LaunchAgent does not invoke Connect automatically.

Disable login startup:

```bash
launchctl bootout "gui/$(id -u)/io.lazylead.vpn.autostart"
launchctl disable "gui/$(id -u)/io.lazylead.vpn.autostart"
```

## Updating Yandex Cloud addresses

```bash
python3 scripts/collect_yandex_cloud_routes.py --output build/direct-network
sudo ./scripts/install_direct_routes.sh
```

The `.ru`/`.рф` DNS service learns new addresses as queries arrive. Yandex Cloud
services in other zones use the separate prefix snapshot.
