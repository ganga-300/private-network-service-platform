# Private DNS (dnsmasq)

Runs on Mac 1 (Ganga). It answers DNS queries for the private `.test` domain.
`.test` is used because it is reserved for testing. `.local` is avoided because
it conflicts with macOS mDNS.

## Records

| Name | Resolves to | Meaning |
|---|---|---|
| app.netforge.test | 10.7.17.248 | nginx edge server (Mac 2) |
| api.netforge.test | 10.7.17.248 | nginx edge server (Mac 2) |

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

Expected: ANSWER SECTION shows `10.7.17.248` and SERVER shows `10.7.15.247`.

## Ports

DNS uses 53/UDP for normal queries. Wireshark filter: `dns`.

## Phase 2

### Backup DNS (Extension A)
Mac 4 (Anuradha, 10.7.3.10) runs a second dnsmasq with the same records: [`dnsmasq-backup.conf`](dnsmasq-backup.conf).
Clients list both servers, primary first:

```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.15.247 10.7.3.10
scutil --dns | grep 'nameserver\[' | head -2
```

The records are copied **by hand**. Any change must be made on both Macs, then `sudo brew services restart dnsmasq`
on each (`start` does not reload a running service).

### TTL (Extension B)
`local-ttl=30` on both servers. Without it, dnsmasq answers its own records with TTL 0 and clients never cache them.

```bash
dig app.netforge.test                      # ANSWER shows 30
dscacheutil -q host -a name app.netforge.test   # what macOS has cached
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # flush the client cache
```

### Changing a record (used for Extensions B and E)
```bash
sudo sed -i '' 's#^address=/app.netforge.test/.*#address=/app.netforge.test/<NEW_IP>#' /opt/homebrew/etc/dnsmasq.conf
sudo brew services restart dnsmasq
```
