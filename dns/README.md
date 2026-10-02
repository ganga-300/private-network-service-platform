# Private DNS (dnsmasq)

Runs on Mac 1 (Ganga). It answers DNS queries for the private `.test` domain.
`.test` is used because it is reserved for testing. `.local` is avoided because
it conflicts with macOS mDNS.

## Records

| Name | Resolves to | Meaning |
|---|---|---|
| app.netforge.test | 10.7.18.238 | nginx edge server (Mac 2) |
| api.netforge.test | 10.7.18.238 | nginx edge server (Mac 2) |

Clients never get the backend IPs. They only ever learn the edge IP.

## Setup

```bash
brew install dnsmasq
# copy dns/dnsmasq.conf to /opt/homebrew/etc/dnsmasq.conf
sudo brew services restart dnsmasq
```

Port 53 is a privileged port, so the service needs `sudo`.

## Point clients at this DNS server

System Settings, Network, Wi-Fi, Details, DNS: add `10.7.15.247` as the DNS server.

## Verify

```bash
dig app.netforge.test @10.7.15.247   # direct query to our server
dig app.netforge.test                # uses the system resolver
```

Expected: ANSWER SECTION shows `10.7.18.238` and SERVER shows `10.7.15.247`.

## Ports

DNS uses 53/UDP for normal queries. Wireshark filter: `dns`.
