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
