# NetForge: Private Network Service Platform

Computer Networks Course Project: Phase 1 (Build and Observe) and Phase 2 (Harden, Recover, Troubleshoot)

A private service environment built on four macOS laptops over a local network, with no cloud. A client opens `https://app.netforge.test:8443`, resolves the name through our own DNS server, connects over TLS to an nginx edge, and is load balanced across two backend servers. The whole journey is captured in Wireshark.

> The application stays simple. The network is the project.

## Team

| Member | Phase 1 role | Phase 2 addition | Machine |
|---|---|---|---|
| Ganga | Primary DNS Server + Test Client | TTL, record changes | Mac 1 |
| Alisha | Edge / Reverse Proxy + Load Balancer | Health checks, failover | Mac 2 |
| Pratiti | Backend Server A | Standby edge, pf firewall | Mac 3 |
| Anuradha | Backend Server B + Test Client | Backup DNS, pf firewall | Mac 4 |

## Project Demo Video

[Project Demo Video](https://drive.google.com/file/d/1UlZExhMh6v0b6dZ7keArF0XUAeVMysRz/view?usp=sharing)

## Architecture

```
Client
  → Private DNS (dnsmasq, UDP 53)
  → nginx Edge (HTTPS, TCP 8443)
  → Backend A (:3001) / Backend B (:3002)
```

| Component | Machine | Port |
|---|---|---:|
| Primary DNS (dnsmasq) | Mac 1 | 53 |
| Backup DNS (dnsmasq), Phase 2 | Mac 4 | 53 |
| nginx HTTPS edge | Mac 2 | 8443 |
| Standby nginx edge, Phase 2 | Mac 3 | 8443 |
| Backend A | Mac 3 | 3001 |
| Backend B | Mac 4 | 3002 |

Machine roles and IPs: [`architecture/IP_service_table.md`](architecture/IP_service_table.md)
Written architecture: [`architecture/architecture.md`](architecture/architecture.md)

## Repository structure

| Folder | Contents | Owner |
|---|---|---|
| `architecture/` | Topology, request flow, IP and service table | Ganga |
| `dns/` | dnsmasq configuration | Ganga |
| `nginx/` | Reverse proxy and load balancer config (Phase 1, Phase 2, standby) | Alisha |
| `firewall/` | pf anchor rules for backend isolation, apply and rollback | Pratiti, Anuradha |
| `tools/` | `diagnose.sh`, layer-by-layer troubleshooting | Everyone |
| `tls/` | Certificate setup notes, OpenSSL config, cert script | Alisha |
| `backend-a/` | Backend A source (Python) | Pratiti |
| `backend-b/` | Backend B source (Python) | Anuradha |
| `evidence/` | Screenshots, captures and test scripts, by task | Everyone |
| `report/` | Phase 1 report (PDF), [Phase 2 report](report/PHASE2_REPORT.md) | Everyone |
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

Current IPs: Mac 1 10.7.15.247, Mac 2 10.7.17.248, Mac 3 10.7.28.81, Mac 4 10.7.3.10 (DHCP, so re-check before demos).

```bash
# DNS through our server
dig app.netforge.test

# Each backend directly
curl -i http://10.7.28.81:3001/api/status
curl -i http://10.7.3.10:3002/api/status

# HTTPS through the edge (no -k flag)
curl -i https://app.netforge.test:8443/api/status

# Load balancing: A and B should alternate
bash evidence/04_load_balancing/test-load-balancing.sh

# Caching: Cache-Control max-age=60
bash evidence/06_caching/test-caching.sh

# Phase 2: check every layer at once (resolver, DNS, IP, TCP, TLS, HTTP)
bash tools/diagnose.sh
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
| [`evidence/07_failure`](evidence/07_failure) | Backend A failure and recovery, wrong DNS server, wrong record IP, both backends down (502), wrong port |
| [`evidence/08_backup_dns`](evidence/08_backup_dns) | Ext A: names still resolve through Mac 4 while Mac 1 is down; DNS failure vs app failure |
| [`evidence/09_dns_ttl`](evidence/09_dns_ttl) | Ext B: cached answer vs server answer timeline, flush |
| [`evidence/10_service_isolation`](evidence/10_service_isolation) | Ext C: pf anchor, edge allowed, client blocked, rollback |
| [`evidence/11_ha_failover`](evidence/11_ha_failover) | Ext D: Backend A down, all requests served by B, recovery, edge log |
| [`evidence/12_edge_migration`](evidence/12_edge_migration) | Ext E: DNS cutover to the standby edge, cached vs fresh clients, rollback |
| [`evidence/13_troubleshooting`](evidence/13_troubleshooting) | Ext F: diagnose.sh drills (DNS, TCP, TLS, upstream) and a real 504 incident, see `notes.md` |

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
- [x] Phase 2: Harden and recover (see [PHASE2_PLAN.md](PHASE2_PLAN.md) and [report/PHASE2_REPORT.md](report/PHASE2_REPORT.md))
