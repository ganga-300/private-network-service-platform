# NetForge: Private Network Service Platform

Computer Networks Course Project, Phase 1 (Build and Observe)

A private service environment built on four macOS laptops over a local network, with no cloud. A client opens `https://app.netforge.test:8443`, resolves the name through our own DNS server, connects over TLS to an nginx edge, and is load balanced across two backend servers. The whole journey is captured in Wireshark.

> The application stays simple. The network is the project.

## Team

| Member | Role | Machine |
|---|---|---|
| Ganga | Private DNS Server + Test Client | Mac 1 |
| Alisha | Edge / Reverse Proxy + Load Balancer | Mac 2 |
| Pratiti | Backend Server A | Mac 3 |
| Anuradha | Backend Server B + Test Client | Mac 4 |

# Project Demo Video

[Project Demo Video](https://drive.google.com/file/d/1UlZExhMh6v0b6dZ7keArF0XUAeVMysRz/view?usp=sharing)



## Architecture

```
Client
  → Private DNS (dnsmasq, UDP 53)
  → nginx Edge (HTTPS, TCP 8443)
  → Backend A (:3001) / Backend B (:3002)
```

| Component | Port |
|---|---:|
| DNS (dnsmasq) | 53 |
| nginx HTTPS | 8443 |
| Backend A | 3001 |
| Backend B | 3002 |

Machine roles and IPs: [`architecture/IP_service_table.md`](architecture/IP_service_table.md)
Written architecture: [`architecture/architecture.md`](architecture/architecture.md)

## Repository structure

| Folder | Contents | Owner |
|---|---|---|
| `architecture/` | Topology, request flow, IP and service table | Ganga |
| `dns/` | dnsmasq configuration | Ganga |
| `nginx/` | Reverse proxy and load balancer config | Alisha |
| `tls/` | Certificate setup notes, OpenSSL config, cert script | Alisha |
| `backend-a/` | Backend A source (Python) | Pratiti |
| `backend-b/` | Backend B source (Python) | Anuradha |
| `evidence/` | Screenshots, captures and test scripts, by task | Everyone |
| `report/` | Phase 1 report (PDF) | Everyone |
| `video/` | Phase 1 demo | Everyone |

## Run the backends

Backend A (port 3001) and Backend B (port 3002) bind to all interfaces so other Macs can reach them.

```bash
cd backend-a      # or backend-b
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py
```

| Endpoint | Response |
|---|---|
| `GET /` | Page confirming the service is running |
| `GET /api/status` | `{"backend":"A","status":"ok"}` (or `"B"`) |
| Header | `X-Backend: A` or `X-Backend: B` |

## Verification

Replace the placeholders with the final verified IPs.

```bash
# DNS through our server
dig app.netforge.test

# Each backend directly
curl -i http://10.7.19.184:3001/api/status
curl -i http://10.7.13.88:3002/api/status 

# HTTPS through the edge (no -k flag)
curl -i https://app.netforge.test:8443/api/status

# Load balancing: A and B should alternate
bash evidence/04_load_balancing/test-load-balancing.sh

# Caching: Cache-Control max-age=60
bash evidence/06_caching/test-caching.sh
```

## Evidence

| Folder | What it proves |
|---|---|
| [`evidence/01_dns`](evidence/01_dns) | `dig` output and DNS query/response |
| [`evidence/02_backend`](evidence/02_backend) | Both backends responding with `X-Backend` |
| [`evidence/03_https`](evidence/03_https) | Successful HTTPS request via the domain name |
| [`evidence/04_load_balancing`](evidence/04_load_balancing) | Requests alternating between A and B |
| [`evidence/05_wireshark`](evidence/05_wireshark) | DNS, TCP handshake, TLS handshake, encrypted data, backend traffic |
| [`evidence/06_caching`](evidence/06_caching) | `Cache-Control: public, max-age=60` |
| [`evidence/07_failure`](evidence/07_failure) | Backend A failure and recovery |

## Protocol layers

| Layer | Protocol | Seen in |
|---|---|---|
| Application | DNS, HTTP/1.1, REST | `dig`, `curl -v` |
| Session / Transport | TLS | Handshake in Wireshark |
| Transport | TCP (8443, 3001, 3002), UDP (53) | Three-way handshake, ports |
| Network | IP | Client, DNS, edge, backend addresses |
| Link | Wi-Fi / Ethernet | MAC addresses on the LAN |

## Security note

Private keys (`*.key`) and the CA key are not committed. Only public certificates, configs and scripts are included.

## Roadmap

- [x] Phase 1: Build and observe
- [ ] Phase 2: Harden and recover
