# Lazylead VPN

Lazylead VPN is a small macOS menu bar app for running a Check Point `snx-rs`
VPN client inside a lightweight Lima Linux VM while keeping the macOS host
usable with another VPN client.

The app starts the Lima VM, launches `snx-rs`, opens the Check Point SAML/2FA
URL in the default browser, and applies macOS routes/DNS so corporate services
can be opened from the normal browser, `git`, `kubectl`, `k9s`, and other host
tools.

## What It Does

- Runs the Check Point Linux client inside a Lima VM.
- Keeps Check Point gateway/SSO hosts reachable through the physical network
  even when another macOS VPN changes the default route.
- Routes corporate networks from macOS into the Lima VM after the Check Point
  tunnel is connected.
- Adds scoped `/etc/resolver` entries for corporate DNS zones.
- Provides a native menu bar UI with Connect, Disconnect, and Settings.
- Can install restricted `sudoers` rules so route updates do not ask for an
  admin password on every connect.

## Requirements

- macOS on Apple Silicon.
- Xcode command line tools for building from source.
- Homebrew, if you want the installer bootstrap to install Lima automatically.
- Lima.
- A prepared Lima instance named `lazylead-vpn`.
- `snx-rs` installed inside that VM.
- Check Point `snx-rs` config at:

```text
$HOME/.config/snx-rs/snx-rs.conf
```

inside the Lima VM user account.

## Configuration

The public repository uses placeholder hosts, routes, and DNS values. Put the
real organization-specific values in a local env file and keep that file out of
git.

Default config path:

```text
/usr/local/etc/lazylead-vpn/env
```

Supported variables:

```bash
VPN_BOOTSTRAP_HOSTS="vpn.example.com sso.example.com"
VPN_PUBLIC_DNS_SERVERS="1.1.1.1 9.9.9.9"
VPN_CORPORATE_ROUTES="10.0.0.0 255.0.0.0 10.0.0.1;172.16.0.0 255.240.0.0 172.16.0.1"
VPN_DNS_DOMAINS="corp.example.com internal.example.com"
VPN_DNS_SERVERS="10.0.0.53 10.0.0.54"
VPN_ROUTE_PROBES="10.0.0.1 10.0.0.53"
```

The app itself can also be configured via environment variables:

```bash
LAZYLEAD_VM_NAME="lazylead-vpn"
LAZYLEAD_VM_GATEWAY="192.168.64.2"
LAZYLEAD_SNX_CONFIG_PATH='$HOME/.config/snx-rs/snx-rs.conf'
LAZYLEAD_GATEWAY_PROBE_URL="https://vpn.example.com/clients/"
LAZYLEAD_BOOTSTRAP_PROBE_IP="203.0.113.10"
LAZYLEAD_CORPORATE_PROBE_IP="10.0.0.1"
LAZYLEAD_VPN_CONFIG="/usr/local/etc/lazylead-vpn/env"
```

The IP addresses shown above are placeholders, not secrets:

- `10.0.0.0/8` examples are private RFC1918 ranges.
- `192.168.64.2` is the usual Lima VZ NAT guest address on macOS.
- `203.0.113.10` is from RFC5737 TEST-NET-3 documentation space.
- `1.1.1.1` and `9.9.9.9` are public recursive DNS resolvers.

## Lima VM Setup

The app expects a Lima VM that can run the Linux Check Point client and expose
its tunnel back to the macOS host.

Create a VM from the included neutral template:

```bash
limactl start --name=lazylead-vpn ./examples/lima-vm.yaml
```

Install base tools inside the VM:

```bash
limactl shell lazylead-vpn -- sudo apt-get update
limactl shell lazylead-vpn -- sudo apt-get install -y curl ca-certificates iproute2 iptables dnsutils
```

Install `snx-rs` inside the VM using the package that matches your environment
and your organization's Check Point gateway. Keep downloaded VPN packages and
generated config files outside this repository.

One generic package-install flow looks like this:

```bash
limactl copy /path/to/snx-rs-package.deb lazylead-vpn:/tmp/snx-rs-package.deb
limactl shell lazylead-vpn -- sudo apt-get install -y /tmp/snx-rs-package.deb
```

Create the `snx-rs` config inside the VM according to your organization's
Check Point setup:

```bash
limactl shell lazylead-vpn -- mkdir -p ~/.config/snx-rs
limactl shell lazylead-vpn
$EDITOR ~/.config/snx-rs/snx-rs.conf
```

Then update the local app config on macOS:

```bash
sudo mkdir -p /usr/local/etc/lazylead-vpn
sudo install -m 0644 /path/to/local-lazylead-vpn.env /usr/local/etc/lazylead-vpn/env
```

## Build

```bash
swift run LazyleadVPNCoreSelfTest
./scripts/build_app_bundle.sh
```

The app bundle is written to:

```text
build/Lazylead VPN.app
```

## Run

```bash
open "build/Lazylead VPN.app"
```

Use the menu bar icon:

- `Connect` starts the VM, prepares routes, starts `snx-rs`, and opens the 2FA
  page.
- `Disconnect` stops `snx-rs` and removes corporate host routes/DNS.
- `Settings` shows Lima status, app paths, sudoers status, logs, and the
  current IPv4 routing table.

## Installer Package

```bash
./scripts/build_installer_pkg.sh
```

The unsigned installer package is written to:

```text
dist/LazyleadVPN-0.1.0-arm64.pkg
```

The package installs the app into `/Applications`, copies privileged route
scripts into `/usr/local/libexec/lazylead-vpn`, and installs a narrow
`/etc/sudoers.d/lazylead-vpn` rule for the route commands used by the app.

If Lima is missing and Homebrew is available, the postinstall script attempts
to install Lima. It does not create or configure the Lima VM and does not
install the Check Point client.

## Autostart

For a locally built app:

```bash
./scripts/install_launch_agent.sh
```

Or pass an explicit app path:

```bash
./scripts/install_launch_agent.sh "/Applications/Lazylead VPN.app"
```

## Security Notes

This repository should not contain credentials, VPN client config files,
private keys, session URLs, or diagnostic reports. The `.gitignore` excludes
build artifacts, local VPN probe reports, logs, installer packages, VPN config
files, certificates, and downloaded `.deb` packages.

The app logs state transitions and sanitized events. It should not log
passwords, MFA codes, cookies, or SAML assertions.

Before publishing changes, run:

```bash
rg -n --hidden -S -i "(password|token|secret|api[_-]?key|private[ _-]?key|authorization|bearer|cookie|session)" \
  --glob '!.git/**' --glob '!.build/**' --glob '!build/**' --glob '!dist/**' --glob '!vpn-probe-reports/**'
```

Review any matches manually before pushing.
