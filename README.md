# Lazylead VPN

**English** | [Русский](README.ru.md)

A macOS menu bar app for managing a Lima network gateway.
Current version: **0.2.0**. In the default mode, selected traffic goes directly
through the VM to your internet provider while the Mac's primary VPN stays in use.
**Check Point remains available as a separate mode.**

## Traffic routing

| Traffic | Path in direct mode |
| --- | --- |
| All `.ru` and `.рф` domains and their subdomains | Mac → Lima → internet provider |
| `gov.ru`, `gosuslugi.ru`, `esia.gosuslugi.ru` | Covered by the `.ru` rule |
| Yandex Cloud: published IPv4 ranges, API, console, Object Storage, CDN | Mac → Lima → internet provider, using the installed address snapshot |
| Transmission inside Lima | Lima → internet provider; downloads are saved to `~/Downloads` on the Mac |
| Other Mac traffic | The Mac's normal route, such as Pepper VPN |

The app does not establish its own VPN tunnel or configure Pepper. Separate
system helpers install routes and DNS rules. Lima must be running for these
rules to work. Selected-site routing currently supports **IPv4**.

## Getting started

- **New Mac:** [installation guide](docs/installation.md).
- **Already configured:** [update the app](docs/installation.md#updating-a-configured-mac).
- **Daily use, Transmission, login startup:** [usage guide](docs/usage.md).
- **A site or the VM is unreachable:** [troubleshooting and removing rules](docs/troubleshooting.md).
- **Corporate VPN:** [Check Point mode](docs/checkpoint.md).
- **Network design and limitations:** [architecture](docs/architecture.md).

App menu:

| Item | Action |
| --- | --- |
| `Start Lima (Direct)` | Start the VM and verify that its only IPv4 default route uses `direct0` |
| `Stop Lima` | Stop the VM; selected sites and Transmission become unavailable |
| `Settings…` | View the version, mode, VM, paths, log, and routing table |
| `Quit Lazylead VPN` / `⌘Q` | Quit the app; the VM and system services keep running |

Transmission Web UI: [127.0.0.1:9092/transmission/web/](http://127.0.0.1:9092/transmission/web/).

## Building and checking

Requires Apple Silicon, macOS 14+, Xcode Command Line Tools, and Lima 2+.
Full Xcode is not required to build the app.

```bash
./scripts/prepare_dependencies.sh
swift run LazyleadVPNCoreSelfTest
PYTHONPATH=build/domain-routing/vendor python3 scripts/test_domain_dns.py
python3 scripts/test_host_direct_routes.py
./scripts/build_app_bundle.sh
./scripts/install_app.sh
```

Build output: `build/Lazylead VPN.app`. Installed app: `/Applications/Lazylead VPN.app`.
The version is stored in [`VERSION`](VERSION); the Git revision is recorded in
`Info.plist`. To build an installer package, run `./scripts/build_installer_pkg.sh`.
The package installs only the app; follow the guide to set up the VM and system rules.
Local builds use ad-hoc signing and do not include Developer ID signing or notarization.

Check Point sources and configuration examples use placeholders rather than
working corporate addresses or credentials. Local configuration, keys,
diagnostic reports, and build artifacts are excluded from Git.
