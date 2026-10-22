# Network architecture

[Back to README](../README.md) | [Русский](ru/architecture.md)

The Mac keeps its normal default route, such as Pepper VPN. Lima has two
additional network interfaces: `lima0` receives Mac traffic through VZ NAT,
and `direct0` connects through socket_vmnet to the physical `en0` interface.
The VM's only IPv4 default route and its DNS use `direct0` to reach the provider.

## Components

| Component | Runs on | Purpose |
| --- | --- | --- |
| Lazylead VPN.app | Mac, user | Start/stop the VM and check its default route |
| `io.lazylead.direct-network` | Mac, root | socket_vmnet; socket at `/private/var/run/lazylead-direct.sock` |
| `lazylead-direct-router.service` | VM, root | Restricted IPv4 forwarding/NAT from `lima0` to `direct0` |
| `io.lazylead.gov-dns` | Mac, root | DNS-to-route for `.ru`, `.рф`, `tbank-online.com`, and `codenrock.com`; TCP/UDP `127.0.0.1:1054` |
| systemd-resolved | VM | DNS for the Mac at `192.168.64.2:1053` |
| `io.lazylead.direct-routes` | Mac, root | Install/check the Yandex Cloud prefix snapshot every minute |
| `lazylead-transmission.service` | VM, user | Transmission with a writable virtiofs mount of `~/Downloads` |

The names `gov-dns` and `install_gov_routes.sh` are historical: they now handle
all `.ru` and `.рф` (`xn--p1ai`) domains, plus `tbank-online.com` and `codenrock.com`, including their subdomains.

## DNS-to-route

`/etc/resolver/ru`, `/etc/resolver/xn--p1ai`, `/etc/resolver/tbank-online.com`, and `/etc/resolver/codenrock.com`
select the local DNS service.
It queries DNS through Lima, installs IPv4 routes for the returned addresses,
and only then returns the answer to the application. If route installation
fails, it returns SERVFAIL. CNAME records and HTTPS/SVCB IPv4 hints are included.
AAAA records and IPv6 hints are excluded to prevent connections from bypassing
the IPv4 gateway.

Learned routes are retained for their DNS TTL plus one day and checked every
30 seconds. State and route ownership are stored in
`/var/db/lazylead-domain-dns/routes.json`. The service does not overwrite
conflicting user-defined static routes. It can replace automatically generated
scoped VPN host-cache entries.

## Limitations

- IPv4 is supported; full IPv6 forwarding is not implemented.
- Applications with their own DNS/DoH can bypass the system resolver.
- Routing works by IP: other domains sharing an address may also use Lima.
- External resources outside the selected domains/prefixes follow their own routes.
- Existing connections and browser-owned DNS caches are not redirected retroactively.
- The Yandex Cloud snapshot requires manual updates. New or changed addresses
  outside the snapshot are not covered. Replacing the snapshot does not
  automatically withdraw old prefixes on a running Mac; remove and reinstall
  the rules for a full reset.
- There is no kill switch: stopping the VM does not remove rules, and network
  changes do not guarantee that traffic cannot use the normal Mac route.
- The installation currently assumes `192.168.64.1/2`, `en0`, and ARM64.
- Transmission RPC has no password and is accessible only on loopback. It is
  not intended to expose port 9092 to the LAN or the internet.

## Check Point

Corporate VPN mode is preserved and enabled explicitly. It uses `snx-rs`,
corporate routes/DNS, and browser-based SAML/2FA. Direct mode does not start
Check Point. See [the Check Point guide](checkpoint.md).
