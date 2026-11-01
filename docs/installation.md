# Installation and updates

[Back to README](../README.md) | [Русский](ru/installation.md)

## Updating a configured Mac

If the VM, DNS, and routes are already configured, update the app with:

```bash
git pull --ff-only
swift run LazyleadVPNCoreSelfTest
./scripts/build_app_bundle.sh
./scripts/install_app.sh
```

The script backs up the previous app in `build/`, closes the old app, installs
the new version in `/Applications`, and launches it. The VM is not restarted.
Updating the app does not overwrite network settings or the Transmission queue.

When upgrading from the experimental native-Mac Transmission setup, also
update the Yandex Cloud system helper:

```bash
sudo ./scripts/install_direct_routes.sh
```

It uses the existing `build/direct-network/yandex-cloud-ipv4.txt`, removes only
Lazylead's old scoped `/1` routes and private PF anchor, restores the local VM
path if necessary, and checks access to the Yandex API. The current setup uses
destination routes and Transmission inside Lima. If you do not have the
snapshot, generate it first as described below.

After changing `scripts/domain_dns.py`, update the installed DNS service:

```bash
./scripts/prepare_dependencies.sh
sudo ./scripts/install_gov_routes.sh
```

Despite its historical name, this installer handles all `.ru` and `.рф` domains, plus
`tbank-online.com`, `codenrock.com`, `hideogenius.com`, `ppc.ipchanger.live`, and `vkvideo.cloud`, including their subdomains.

## New Mac: 1. Prerequisites

Supported setup: Apple Silicon, macOS 14+, and Ubuntu 24.04 ARM64 in Lima 2+.
Install [Homebrew](https://brew.sh/) before running `brew install lima` below.
This guide uses the VM name `lazylead-vpn`. If you already have a VM with a
different name, such as `existing-vpn`, use that name in all commands and
settings. Do not replace an existing VM configuration with a second setup.

```bash
xcode-select --install
brew install lima
git clone https://github.com/ehlyzov/lazylead-vpn.git
cd lazylead-vpn
./scripts/prepare_dependencies.sh
```

`prepare_dependencies.sh` downloads the official socket_vmnet 1.2.2 release
and dnslib 0.9.26, verifies SHA-256 checksums, and stores them in `build/`.
System rules are installed by separate `sudo` commands. These installers do
not add sudoers rules.

## 2. Direct VM network

Check that the Mac's physical internet connection uses `en0`:

```bash
networksetup -listallhardwareports
```

The current socket_vmnet implementation is bound to `en0`. If your physical
interface is different, adapt `scripts/install_direct_network.sh` and the
checks before running the setup commands.

```bash
sudo ./scripts/install_direct_network.sh
python3 scripts/create_direct_vm_config.py
limactl validate build/lima-direct.yaml
limactl start --name=lazylead-vpn build/lima-direct.yaml
```

The generator creates a separate YAML file with `direct0`, `vzNAT`, a writable
virtiofs mount of your `~/Downloads`, local port 9092, and a provisioning script.
It does not modify existing VMs. `vm_direct_network.sh` runs when the VM starts
and removes host-network routes/DNS from its internet path.

Check the addresses:

```bash
limactl shell --workdir / lazylead-vpn ip -4 -brief address
limactl shell --workdir / lazylead-vpn ip -4 route show default
```

Expect a single IPv4 default route through `direct0`, a `lima0` address of
`192.168.64.2/24`, and `192.168.64.1/24` on the Mac. These two addresses are
fixed in the current implementation. If DHCP assigned a different address,
stop and align the helper addresses before installing routes.

## 3. Router and DNS inside the VM

```bash
limactl shell --workdir / lazylead-vpn sudo apt-get update
limactl shell --workdir / lazylead-vpn sudo apt-get install -y iptables curl dnsutils python3-yaml
limactl copy scripts/vm_direct_router.sh lazylead-vpn:/tmp/lazylead-direct-router
limactl copy packaging/lazylead-direct-router.service lazylead-vpn:/tmp/lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn sudo install -m 0755 /tmp/lazylead-direct-router /usr/local/sbin/lazylead-direct-router
limactl shell --workdir / lazylead-vpn sudo install -m 0644 /tmp/lazylead-direct-router.service /etc/systemd/system/lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn sudo systemctl daemon-reload
limactl shell --workdir / lazylead-vpn sudo systemctl enable --now lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn sudo bash -s < scripts/vm_domain_dns.sh
```

The router allows forwarding only from `192.168.64.1` through `lima0` to
`direct0`, applies NAT, and permits return packets for established connections.
DNS listens at `192.168.64.2:1053` over TCP and UDP.

## 4. Mac routing rules

All `.ru` and `.рф` domains, plus `tbank-online.com`, `codenrock.com`, `hideogenius.com`, `ppc.ipchanger.live`, and `vkvideo.cloud`, including their subdomains:

```bash
sudo ./scripts/install_gov_routes.sh
```

Successful output: `VERIFIED: .ru, .рф, tbank-online.com, codenrock.com, hideogenius.com, ppc.ipchanger.live and vkvideo.cloud with their subdomains use Lima (IPv4).`

Yandex Cloud, including services outside `.ru`:

```bash
python3 scripts/collect_yandex_cloud_routes.py --output build/direct-network
sudo ./scripts/install_direct_routes.sh
```

The collector reads official ranges, CDN prefixes, and the API directory.
Its HTTP requests use `en0` by default; `--interface ''` uses the Mac's normal
route. The snapshot is not refreshed automatically: rerun both commands
periodically. The installer verifies public IPv4 prefixes and API access.

## 5. Transmission with files on the Mac

```bash
GUEST_USER="$(limactl shell --workdir / lazylead-vpn id -un)"
limactl shell --workdir / lazylead-vpn sudo bash -s -- "$GUEST_USER" < scripts/vm_transmission.sh
open http://127.0.0.1:9092/transmission/web/
```

Completed files are saved in `~/Downloads`; incomplete files are in
`~/Downloads/.transmission-incomplete`. The native Mac Transmission queue is
not imported automatically. RPC is available only on guest and Mac loopback.
Application state is stored in `/var/lib/lazylead-transmission` inside the VM.

## 6. The app

```bash
./scripts/build_app_bundle.sh
./scripts/install_app.sh
```

The app reads `/usr/local/etc/lazylead-vpn/env`:

```text
LAZYLEAD_ROUTING_MODE=direct
LAZYLEAD_VM_NAME=lazylead-vpn
LAZYLEAD_VM_GATEWAY=192.168.64.2
```

Create this file on a new Mac with:

```bash
sudo mkdir -p /usr/local/etc/lazylead-vpn
sudo install -m 0644 examples/direct.env.example /usr/local/etc/lazylead-vpn/env
```

For an existing installation, edit only the required lines and preserve any
corporate settings. Process environment variables take precedence over the
file. Set `LAZYLEAD_VPN_CONFIG` to use another path. Restart the app after
changing the routing mode or VM name.

To build a `.pkg`, run `./scripts/build_installer_pkg.sh`. The package in `dist/`
installs the app; it does not create a VM, change routes, or configure Check Point.
