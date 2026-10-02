# Private Network Service Platform (netforge)

**Team NetForge** | Computer Networks course project

A small private service environment built from scratch on a local network, with no cloud and no pre-configured servers. A client types a private domain name, and we trace and prove every step of the request using packet capture tools.

> **The application stays simple. The network is the project.**

## What this project demonstrates

A client on the team LAN can:

1. Type `https://app.netforge.test` in a browser or `curl`
2. Resolve the name through **our own DNS server**
3. Open a **TLS-secured** connection to our **reverse proxy**
4. Get a response from **Backend A or Backend B**, load balanced
5. Have the whole journey **observed in Wireshark** (DNS, TCP, TLS, HTTP)

## Architecture

| Machine | Role | Services | Cloud equivalent |
|---------|------|----------|------------------|
| Mac 1 | Private DNS + test client | dnsmasq, dig, curl | Route 53 |
| Mac 2 | Edge reverse proxy + load balancer | nginx, TLS certificate | AWS ALB / CDN edge |
| Mac 3 | Backend A | REST API on port 3001 | App server instance A |
| Mac 4 | Backend B + test client | REST API on port 3002 | App server instance B |

```
Client ──DNS query (UDP 53)──▶ Mac 1 (dnsmasq)
   │                               │ returns Mac 2's IP
   ▼
Client ──HTTPS (TCP 443/8443)──▶ Mac 2 (nginx, TLS termination)
                                   ├──▶ Mac 3 (Backend A :3001)
                                   └──▶ Mac 4 (Backend B :3002)
```

Topology diagram: [`docs/diagrams/topology.png`](docs/diagrams/topology.png)
IP and service inventory: [`docs/ip-service-inventory.md`](docs/ip-service-inventory.md)

## Tech stack

- **DNS:** dnsmasq
- **Edge / load balancer:** nginx (round-robin upstream)
- **TLS:** OpenSSL, local CA, SAN certificate for `app.netforge.test`
- **Backends:** Node.js (or Python) REST API
- **Observability:** Wireshark, tcpdump, curl, dig, browser DevTools

## Repository structure

```
.
├── docs/            Architecture, IP inventory, diagrams
├── backend/         Backend A and Backend B source code
├── config/
│   ├── dns/         dnsmasq.conf
│   ├── nginx/       nginx.conf
│   └── tls/         CA and certificate setup notes, openssl.cnf
├── scripts/         Cert generation and test scripts
└── evidence/        Outputs, screenshots, Wireshark captures
```

## Setup (in order)

Replace `<MAC1_IP>`, `<MAC2_IP>`, `<MAC3_IP>`, `<MAC4_IP>` with the real addresses from the inventory doc.

### 1. LAN

Connect all Macs to the same private Wi-Fi, record each IP, and verify with `ping` between every pair.

### 2. DNS (Mac 1)

```bash
brew install dnsmasq
```

Add to `dnsmasq.conf` (see [`config/dns/dnsmasq.conf`](config/dns/dnsmasq.conf)):

```
address=/app.netforge.test/<MAC2_IP>
address=/api.netforge.test/<MAC2_IP>
```

Restart the service and set Mac 1 as the DNS server on the other client Macs (System Settings → Network → DNS). Verify:

```bash
dig app.netforge.test
```

### 3. Backends (Mac 3 and Mac 4)

Each backend binds to `0.0.0.0` (not `127.0.0.1`) so other machines can reach it.

```bash
cd backend/backend-a && npm install && node server.js   # port 3001
cd backend/backend-b && npm install && node server.js   # port 3002
```

| Endpoint | Response |
|----------|----------|
| `GET /` | Page or JSON confirming the service is running |
| `GET /api/status` | `{ "backend": "A", "status": "ok" }` |
| Header | `X-Backend: A` or `X-Backend: B` |

Caching: at least one endpoint returns `Cache-Control` (and optionally `ETag`).

### 4. TLS (Mac 2)

Create a local CA, then a server certificate with `app.netforge.test` in the SAN. Full steps are in [`config/tls/README.md`](config/tls/README.md), and the commands are in [`scripts/generate-certs.sh`](scripts/generate-certs.sh).

Install the **CA certificate** (never the private key) in the trust store of every client Mac:

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ca.crt
```

### 5. nginx edge (Mac 2)

Use [`config/nginx/nginx.conf`](config/nginx/nginx.conf). It terminates TLS and load balances across both backends:

```nginx
upstream backends {
    server <MAC3_IP>:3001;
    server <MAC4_IP>:3002;
}

server {
    listen 443 ssl;
    server_name app.netforge.test api.netforge.test;
    ...
}
```

```bash
nginx -t && brew services restart nginx
```

## Verification

Run from a client Mac. No `-k` flag, and no IP address in the URL.

```bash
# DNS resolution through our server
dig app.netforge.test

# HTTPS with a trusted certificate
curl -v https://app.netforge.test/api/status

# Load balancing: A and B should alternate
for i in {1..10}; do curl -sI https://app.netforge.test | grep -i x-backend; done

# Caching: Cache-Control, then a conditional request for 304
curl -I https://app.netforge.test/
```

Helper scripts: [`scripts/test-load-balancing.sh`](scripts/test-load-balancing.sh), [`scripts/test-caching.sh`](scripts/test-caching.sh).

## Protocol layer mapping

| Layer | Protocol | Where we see it |
|-------|----------|-----------------|
| Application | DNS, HTTP/1.1 (HTTP/2 if enabled), REST | `dig`, `curl -v` |
| Session / Transport | TLS | ClientHello to Finished in Wireshark |
| Transport | TCP (443), UDP (53) | Three-way handshake, ports, seq/ack numbers |
| Network | IP | Client, DNS, edge and backend IPs |
| Link | Ethernet / Wi-Fi | MAC addresses on the LAN |

## Evidence

All proof is in [`evidence/`](evidence/), organised by task:

| Folder | Contents |
|--------|----------|
| `01-lan-setup` | IP configs, ping results |
| `02-dns` | `dig` / `nslookup` output |
| `03-https` | `curl -v` output, browser screenshots |
| `04-load-balancing` | A/B alternating responses |
| `05-wireshark` | DNS, TCP handshake, TLS handshake captures |
| `06-caching` | `Cache-Control`, `ETag`, 200 vs 304 |
| `07-failure-demos` | Wrong DNS, wrong IP, wrong port, 502 |

## Failure demonstrations

| Scenario | What it shows |
|----------|---------------|
| Wrong DNS server on client | Name lookup fails but IP connectivity still works, so DNS and IP are independent |
| DNS record points to wrong IP | Resolution succeeds but traffic goes to the wrong host, so DNS is a directory, not a connection |
| One backend stopped | Edge keeps serving through the remaining backend |
| Both backends stopped | `502 Bad Gateway` from the edge while DNS and TLS still work |
| Wrong port on client | Host is reachable but the TCP connection fails, so ports and IPs are separate identifiers |

## Team NetForge

| Name | Role / Machine |
|------|----------------|
| Ganga Raghuwanshi | Mac 1: DNS |
| Alisha Gupta | Mac 2: nginx + TLS |
| Pratiti Paul | Mac 3: Backend A |
| Anuradha Raghuwanshi | Mac 4: Backend B |

## Security note

Private keys (`*.key`) and the CA key are **not** committed to this repo. Only public certificates, configs, and scripts are included.

## Roadmap

- [x] Phase 1: Build and observe (LAN, DNS, backends, load balancer, TLS, caching, packet analysis)
- [ ] Phase 2: Harden and recover (backup DNS, TTL, service isolation, HA failover, edge migration)
