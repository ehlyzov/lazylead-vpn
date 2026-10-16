# Changelog

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
