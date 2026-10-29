# Changelog

## Unreleased

- Repair owned DNS host routes that macOS rebinds to the wrong interface after Lima restarts; refuse new routes while the VM gateway has no local bridge.

## 0.4.0 — 2026-10-23

- Added persistent received/sent traffic totals and live speeds for the Lima uplink and Mac-facing link in Direct mode.
- Collection runs while the menu-bar app is open, even with the routes window closed; history is separated by VM, gateway and mode.
- Detects guest/interface restarts, retains totals during outages, and marks possible gaps without treating unavailable counters as zero speed.
- Documents overlapping counters, measurement periods and the difference from Pepper VPN/provider billing.

- Route `codenrock.com` and all its subdomains through the Lima DNS-to-route service.
- Route `tbank-online.com` and all its subdomains through the Lima DNS-to-route service.

## 0.3.0 — 2026-10-16

- Added a native `Traffic & Routes…` window in the menu bar and Settings.
- Shows installed domain rules, Yandex Cloud snapshot counts, guest Transmission status, and the Mac's default interface.
- Lists exact installed IPv4 routes through the configured Lima gateway, with CIDR-aware IP search, scope labels, copy, and background refresh.
- Separates configuration from VM availability and does not claim to monitor live traffic.
- Opens the routing overview on first launch; `--show-routes` opens it explicitly.

## 0.2.0 — 2026-10-16

- Direct Lima uplink through socket_vmnet; the Mac's primary VPN keeps its default route.
- DNS-to-route for all `.ru` and `.рф` domains, including subdomains and IDNs, with routes installed before DNS answers are returned.
- Published Yandex Cloud IPv4 range/API snapshots, route checks, and an API connectivity check during installation.
- Transmission inside Lima, a local Web UI, and downloads saved to `~/Downloads` on the Mac.
- Separate commands to start/stop Lima and an explicit app quit action.
- Check Point/SAML preserved as an opt-in mode; automatic legacy sudoers installation removed from the `.pkg`.
- Migration removes the obsolete native-Transmission scoped `/1` routes and private PF anchor when updating the network helper.
- VM configuration generator, app installation with backup, and version/Git revision metadata in the bundle.
- Installation, usage, troubleshooting, architecture, and Check Point guides; CI for Swift, DNS, and host-route migration.

Limitations: selected routes use IPv4, the Yandex Cloud snapshot requires manual
updates, and applications with their own DoH need separate verification.
End-to-end corporate SAML/2FA login was not tested.
