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

The route table describes configuration; it is not an end-to-end connectivity test. A stopped VM, custom application DNS, more-specific
routes, or a shared destination IP can affect the actual path. Snapshot prefix
counts can exceed the number of matching installed routes because overlapping
prefixes can share a route. Domain names cannot be recovered from an IP-only
routing table, so individual IPs are not presented as verified domain matches.

## Traffic counters

The **Measured traffic** panel in `Traffic & Routes…` shows received/sent totals
and current speeds in Direct mode. Collection starts automatically when the
menu-bar app opens and continues with the window closed, approximately every
five seconds while the Mac is awake. The first successful sample is the zero
baseline: traffic from before tracking began is excluded.

- **Lima uplink** reads `direct0` interface bytes, including Transmission, VM apps,
  traffic forwarded for the Mac, protocol overhead and local network traffic.
- **Mac ↔ Lima link** reads the guest interface holding the configured gateway,
  with directions shown from the Mac's perspective: received means delivered to
  the Mac. It includes local DNS and other link traffic. It overlaps the uplink;
  **do not add the rows**. It is not a separate website or application breakdown.

These counters do not measure Pepper VPN usage or reproduce provider billing.
They read interface bytes across protocols, independently of the IPv4 route table.
The app collects them locally without making internet downloads or changing routes.

The displayed start time and last-sample time identify the measurement period.
History is stored per VM/gateway/mode in
`~/Library/Application Support/Lazylead VPN/Traffic/` and survives app restarts.
After reopening the app, counter growth while it was closed is recovered if the
same guest interfaces still exist. A boot ID and interface index detect restarts;
new interface bytes are added, and a warning marks possible missing traffic before
an unobserved restart. A long sampling gap has no current-speed estimate.

When the VM is stopped or unreachable, or its only IPv4 default route is not
`direct0`, the panel retains saved totals, shows the last sample and reports
unavailable counters rather than zero speed. Check Point remains available, with
traffic accounting explicitly unavailable in that mode. No system-helper update
or administrator password is needed for these counters.

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
