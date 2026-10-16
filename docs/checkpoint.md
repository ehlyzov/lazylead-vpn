# Check Point mode

[Back to README](../README.md) | [Русский](ru/checkpoint.md)

Check Point support is preserved and enabled explicitly. The app's default
mode is a direct gateway to the internet provider through Lima.

## Preparation

You need a Lima VM with `snx-rs`, a working client configuration inside that VM,
and your organization's corporate network settings. Use a separate VM for
Check Point: direct-mode provisioning disables `snx-rs.service` and removes
routes through the host network.

A neutral template is included for a new corporate VM:

```bash
limactl start --name=lazylead-checkpoint examples/lima-vm.yaml
limactl shell --workdir / lazylead-checkpoint sudo apt-get update
limactl shell --workdir / lazylead-checkpoint sudo apt-get install -y curl ca-certificates iproute2 iptables dnsutils
limactl copy /path/to/snx-rs-package.deb lazylead-checkpoint:/tmp/snx-rs-package.deb
limactl shell --workdir / lazylead-checkpoint sudo apt-get install -y /tmp/snx-rs-package.deb
```

Choose an `snx-rs` package for ARM64 and your Ubuntu version. Create its
configuration inside the guest according to your organization's requirements,
for example at `$HOME/.config/snx-rs/snx-rs.conf`. Keep passwords, certificates,
and the real configuration out of this repository.

If another VZ VM already uses `192.168.64.2`, the corporate VM needs a different
address. Set it in `LAZYLEAD_VM_GATEWAY`. Before switching, [remove direct-mode
rules](troubleshooting.md#removing-rules) if needed, so saved routes do not point
to a VM serving a different purpose.

## Mac configuration

The app and legacy helpers read `/usr/local/etc/lazylead-vpn/env`. The following
example uses public and documentation-only values; replace them with your
organization's settings:

```bash
LAZYLEAD_ROUTING_MODE=checkpoint
LAZYLEAD_VM_NAME=lazylead-checkpoint
LAZYLEAD_VM_GATEWAY=192.168.64.2
LAZYLEAD_SNX_CONFIG_PATH='$HOME/.config/snx-rs/snx-rs.conf'
LAZYLEAD_GATEWAY_PROBE_URL=https://vpn.example.com/clients/
LAZYLEAD_BOOTSTRAP_PROBE_IP=203.0.113.10
LAZYLEAD_CORPORATE_PROBE_IP=10.0.0.1
LAZYLEAD_SAML_BROWSER_APP=Safari
VPN_BOOTSTRAP_HOSTS="vpn.example.com sso.example.com"
VPN_PUBLIC_DNS_SERVERS="1.1.1.1 9.9.9.9"
VPN_CORPORATE_ROUTES="10.0.0.0 255.0.0.0 10.0.0.1;172.16.0.0 255.240.0.0 172.16.0.1"
VPN_DNS_DOMAINS="corp.example.com internal.example.com"
VPN_DNS_SERVERS="10.0.0.53 10.0.0.54"
VPN_ROUTE_PROBES="10.0.0.1 10.0.0.53"
```

Restart Lazylead VPN. The menu will show `Connect` and `Disconnect`.

- `Connect` starts the VM, prepares bootstrap routes, starts `snx-rs`, opens
  the SAML/2FA browser page, and installs corporate routes/DNS after connecting.
- `Disconnect` stops `snx-rs` and removes corporate host routes/DNS. Bootstrap
  routes remain installed for the next connection.
- `Settings…` shows the mode and can reopen the latest 2FA page.
- `Quit` closes the app; use `Disconnect` first to shut down the tunnel.

Administrator prompts when changing routes are expected. If needed, explicitly
install the restricted sudoers rules with
`sudo ./scripts/install_passwordless_sudo.sh`. The main `.pkg` no longer installs
them automatically. Direct mode does not need these rules.

To return to direct mode, restore `LAZYLEAD_ROUTING_MODE=direct`, the direct VM's
name, and its address. Restart the app and install the required rules using the
[installation guide](installation.md).

End-to-end corporate SAML/2FA login against a working Check Point gateway was
not tested for release 0.2.0. The mode's code, configuration options, and build
checks have been preserved.
