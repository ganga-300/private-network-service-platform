# NetForge: Phase 2 Final Report (Harden, Recover, Troubleshoot)

**Team:** Ganga (Mac 1), Alisha (Mac 2), Pratiti (Mac 3), Anuradha (Mac 4)
**Tests run:** 23 Nov 2026, 19:00–22:00 IST, on the lab Wi-Fi (10.7.0.0/19)

> **DRAFT.** This was drafted from our test logs. Each member must reread it, and **rewrite the learning paragraphs in Section 5 in their own words** before we submit (the viva checks personal understanding).

---

## 1. Summary

Phase 2 builds on the Phase 1 network without rebuilding it. We added:
- a backup DNS server
- a visible 30 s DNS TTL
- firewall isolation of the backends
- passive health checks with automatic failover at the edge
- a standby edge reachable by DNS cutover
- a layer-by-layer diagnosis script

Every extension was demonstrated with timestamped evidence and then rolled back to a clean state.

| Gate item (from the brief) | Result | Evidence |
|---|---|---|
| Backup DNS | ✅ Names kept resolving with the primary stopped | `evidence/08_backup_dns/` |
| TTL behaviour | ✅ Old answer served for ~16 s after the change, new one after expiry; flush gives the new one immediately | `evidence/09_dns_ttl/` |
| Service isolation | ✅ Edge allowed, client blocked (timeout), rolled back | `evidence/10_service_isolation/` |
| HA failover | ✅ 10 out of 10 requests served by B while A was down; A/B resumed after restart | `evidence/11_ha_failover/` |
| Edge migration | ✅ Cached client stayed on the old edge for ~29 s, then moved; no failed request | `evidence/12_edge_migration/` |
| Troubleshooting | ✅ 4 drills (DNS, TCP, TLS, upstream) + 1 real incident | `evidence/13_troubleshooting/` |

## 2. What changed from Phase 1

| Area | Phase 1 | Phase 2 |
|---|---|---|
| IPs | Mac 2 .18.238, Mac 3 .19.184, Mac 4 .13.88 | New DHCP leases: Mac 2 **10.7.17.248**, Mac 3 **10.7.28.81**, Mac 4 **10.7.3.10**. Updated in the DNS, nginx and docs. |
| DNS servers | Mac 1 only | Mac 1 (primary) + **Mac 4 (backup)**, with identical records |
| Client resolvers | Mac 1 (Mac 4 also had 1.1.1.1 as second) | `10.7.15.247` then `10.7.3.10` on Mac 1, 2 and 4. We removed 1.1.1.1 because a public resolver answers NXDOMAIN for `.test`. |
| DNS TTL | 0 (dnsmasq default for local records, so clients never cached) | **`local-ttl=30`** |
| Edge config | Round robin, default retry | `max_fails=1 fail_timeout=10s`, `proxy_next_upstream error timeout http_502 http_503 http_504`, `proxy_next_upstream_tries 2`, `proxy_connect_timeout 2s`, `proxy_read_timeout 5s`, `X-Edge` header, upstream access log |
| Standby edge | None (a half-finished attempt from 22 Nov ran as root with an unknown config) | Clean nginx on Mac 3 with the same cert (fingerprint `7E:2E:…:A9:C8`) and config, `X-Edge: standby-mac3` |
| Backend access | Any LAN host could reach :3001/:3002 directly | pf anchor allows only the edge. It was applied for the demo and then rolled back, as the brief requires. |
| Tooling | Manual commands | `tools/diagnose.sh` |

## 3. Resilience tests and results

### Ext D: HA failover (Mac 2 config, Mac 3 stopped, Mac 4 client)

| Time | Action | Result |
|---|---|---|
| 19:11:16 | Both backends up, 10 requests | A, B, A, B … all HTTP 200 |
| 19:26:09 | Backend A stopped (port 3001 not listening) | none |
| 19:26:45 | 10 requests | **10 out of 10 served by B, all 200**. One request took 1.19 s: it paid for the failed attempt on A. |
| 19:26:47 | Edge log | `upstream=10.7.28.81:3001, 10.7.3.10:3002 upstream_status=502, 200`: nginx retried on B |
| 19:28:29 | A restarted, 10 requests | A/B alternating again (A came back within `fail_timeout` = 10 s) |
| 19:30:44 | **Both** backends stopped | DNS, TCP and TLS succeed, then `502 Bad Gateway` with `X-Edge: primary-mac2` |

### Ext A: backup DNS (Mac 4 backup, Mac 2 client)

| Time | Action | Result |
|---|---|---|
| 19:43:13 | Normal | `SERVER: 10.7.15.247` (primary) |
| (19:4x) | `brew services stop dnsmasq` on Mac 1 | none |
| 19:44:31 | Query to Mac 1 directly | `connection timed out; no servers could be reached` |
| 19:44:31 | Normal `dig` | Answer `10.7.17.248` from **`SERVER: 10.7.3.10`** (backup) |
| 19:51:54 | `curl` (after fixing the backends, see 4.0) | HTTP 200, still resolved through the backup |
| 19:56:06 | Backup also stopped | `curl` fails to resolve (exit 28: resolution timed out); `curl --resolve` straight to the IP gets **HTTP 200** |
| 20:43:48 | Both DNS servers restored | `SERVER: 10.7.15.247` again |

**DNS failure vs application failure.** At 19:56 the name couldn't be resolved, yet the service was healthy (HTTP 200 when we skipped DNS). At 19:30 the name resolved and TLS worked, but the application returned 502. Each kind of failure shows up at a different layer.

### Ext B: TTL and changing a record (`api.netforge.test`, Mac 2 client)

| Time | macOS cache (`dscacheutil`) | DNS server (`dig @Mac1`) |
|---|---|---|
| 20:48:43 – 20:49:04 | 10.7.17.248 | 10.7.17.248 |
| *20:49:08: record changed on Mac 1 and Mac 4* | | |
| 20:49:09 – 20:49:19 | **10.7.17.248 (stale, cached)** | **10.7.28.81 (new)** |
| 20:49:25 onward | 10.7.28.81 | 10.7.28.81 |

The stale window was ~16 s, not the full 30. The cached entry was last refreshed around 20:48:55, so its 30 s had partly run out when the record changed. A client keeps a stale answer for **at most** one TTL.

Flush test at 20:54:03: `before flush (cached): 10.7.28.81`, then 1 s later `after flush (fresh): 10.7.17.248`.

### Ext C: service isolation (pf on Mac 3 and Mac 4)

| Time | Test | Result |
|---|---|---|
| 21:05 | Before: client (Mac 1) → :3001 and :3002 directly | 200, 200 (the gap we're closing) |
| 21:09 / 21:13 | pf anchor loaded on Mac 3 / Mac 4 | `pf enabled`; anchor shows `pass … from 10.7.17.248 … flags S/SA keep state` and `block drop …`; the `com.apple/*` anchors are still loaded |
| 21:14:58 | Edge (Mac 2) → backends | 200, 200 |
| 21:15:49 | Client (Mac 1) → backends | Ping OK; **:3001 and :3002 time out** (curl exit 28) |
| 21:16:57 | Client → `https://app.netforge.test:8443` | A/B alternating, all 200 |
| 21:20 | Rollback on both | `pf disabled`, `Status: Disabled`, netforge count 0 |
| 21:21:22 | Client → backends directly | 200, 200 |

Method, as advised by our faculty: rules go in their own file `/etc/pf.anchors/netforge`, referenced from `/etc/pf.conf` with `anchor` and `load anchor` lines. We took a backup first and did a dry run (`pfctl -vnf`) before loading. The `pfctl -f` warning about flushing rules is harmless here, because the file we load is the system file itself and still contains every Apple anchor.

### Ext E: DNS-based edge migration (Mac 2 → Mac 3)

| Time | Event | Mac 2 (cached client) |
|---|---|---|
| 21:34:12 | Standby tested directly with `curl --resolve` | `SSL certificate verify ok`, 200, `X-Edge: standby-mac3` |
| 21:37:52 – 21:38:28 | Loop running | `edge_ip=10.7.17.248  X-Edge=primary-mac2  HTTP 200` |
| 21:38:06 / 21:38:10 | `app` record → 10.7.28.81 on Mac 1 / Mac 4 | **still primary-mac2** (cached answer) |
| 21:38:35 onward | none | `edge_ip=10.7.28.81  X-Edge=standby-mac3  HTTP 200` |
| 21:39:21 | Mac 4 (cache flushed) | standby-mac3, 200 |
| 21:42:44 | Rolled back | primary-mac2, 200 |

The standby's log shows requests from Mac 2 from 21:38:35 and from Mac 4 at 21:39:21, round-robined across A and B. **Every request in the migration returned 200.** Clients with a cached answer kept using the old edge for up to one TTL, which is the expected cost of moving traffic with DNS.

*Limitation:* Mac 4's "fresh client" check ran ~70 s after the change, when the TTL had already run out anyway. The Ext B flush test (20:54) is our proof that flushing gives the new answer immediately.

## 4. Troubleshooting findings (Ext F)

**Method.** `tools/diagnose.sh` checks the layers in order: resolver config → DNS → IP (ping) → TCP (`nc`) → TLS (`curl -v`) → HTTP. The first FAIL is the faulty layer, because every layer above it depends on it.

| # | Fault | First failing layer | Key evidence | Fix |
|---|---|---|---|---|
| 0 | **Real incident:** both backends left stopped after the 502 test | Application/backend | `504 Gateway Time-out`. nginx error.log: B `Connection refused (61)`, A `Operation timed out (60)`. `nc`: 3002 refused, 3001 timed out. | Restarted both backends |
| 1 | dnsmasq stopped on both DNS servers | DNS | Neither server answers | Start dnsmasq |
| 2 | nginx stopped on Mac 2 | TCP | DNS and ping OK; `Connection refused` on 8443 | Start nginx |
| 3 | `ssl` removed from `listen 8443` | TLS | TCP OK; `tlsv1 alert protocol version` after the ClientHello | Restore `ssl` |
| 4 | Upstream ports 3009/3008 | Application/upstream | DNS, TCP and TLS OK; `502`; edge log `no live upstreams`; config shows the wrong ports | Restore 3001/3002 |

**What we learned from the real incident (0):**
- A **refused** connection gives **502**; a **timed-out** one gives **504**. nginx tried B first (refused), then waited 2 s on A (timed out), so the final answer was 504.
- Mac 3 should have refused, but it timed out. Its firewall stealth mode was off and pf was disabled, but its ping was 121 ms against ~8 ms for the other Macs. We think slow Wi-Fi delayed the "refused" reply past nginx's 2 s connect timeout. **This is our best explanation, not proven.**
- Lessons: keep each backend running in its own visible Terminal tab, and run the health check after every failure test.

**Other findings during Phase 2:**
- **DHCP changed three IPs overnight.** The first symptom was that pings to the old addresses failed, so the network layer was wrong before anything else was even tested.
- **Mac 4's dnsmasq kept running its old config.** `brew services start` said "already started" and didn't reload, so the backup answered with a stale IP (10.7.28.81). We found it because the backup's answer didn't match the primary's, and fixed it with `restart`.
- **Mac 3's leftover nginx was running as root.** Its config, log folder and pid file were root-owned, so editing them as a normal user failed with "permission denied". We stopped it with `kill -QUIT <pid>` and now manage it with `sudo`.
- **macOS LibreSSL differs from OpenSSL.** `openssl x509 -ext` isn't supported, and a TLS-to-plain-HTTP mismatch shows up as `alert protocol version`, not `wrong version number`.

## 5. Learning summary (one paragraph per extension)

> Each member rewrites these in their own words.

**A: Backup DNS.** A client's resolver list is a list of alternatives. When the first server doesn't answer, the resolver retries the next, so a second server with the same records keeps names resolving when the primary is down. The records must be identical: a backup that answers differently is worse than no backup, as we saw when Mac 4 briefly served an old IP. A DNS failure and an application failure look different. With DNS down, the name doesn't resolve but the service is still reachable by IP. With the application down, the name resolves and TLS works, but the edge returns 502 or 504.

**B: TTL.** The TTL is the server's instruction for how long an answer may be cached. Until it runs out, a client uses its cached answer even after the record has changed on the server, so `dig` (which asks the server) and the OS cache can disagree. Flushing the cache ends that early on one machine. In production, teams lower the TTL ahead of a migration so the change spreads quickly, then raise it again to reduce DNS load.

**C: Service isolation.** The backends were reachable from any machine on the LAN, which bypasses TLS and the load balancer. A pf anchor that only allows the edge's IP to reach 3001/3002 makes nginx the single entry point. Using `block drop` means a blocked client sees a timeout rather than "connection refused". That tells a firewall apart from a stopped service. Keeping the rules in their own anchor file means Apple's system rules are never touched, and rollback is a single file restore.

**D: HA failover.** Open-source nginx does passive health checking: it notices a dead backend when a real request fails, marks it down for `fail_timeout`, and retries the request on the other backend, so the user still gets a 200. Only the first request pays the cost of the failed attempt. The edge itself is still a single point of failure.

**E: Edge migration.** A standby edge with the same certificate and config can take over by changing one DNS record. The switch is gradual: clients holding a cached answer keep using the old edge for up to one TTL, so the old edge must stay up during that window. A floating IP (VRRP) or anycast would avoid the DNS wait.

**F: Troubleshooting.** Working through the layers in order from the bottom turns guesswork into a short checklist: the first layer that fails is where the problem is. The exact error matters. "Refused" means nothing is listening; "timed out" means a firewall, a sleeping host or a bad link; a TLS protocol alert means the port isn't speaking TLS; 502/504 means the edge works but can't reach the backends.

## 6. Known gaps and next steps

- [ ] Screenshots not taken yet: `evidence/00_lan/` (ping matrix with the new IPs), and `08_backup_dns/01, 02, 04` (backup DNS running, client listing two servers, primary stopped).
- [ ] Re-check every IP right before the evaluation; update the DNS records, nginx upstreams and pf rules if DHCP has changed them.
- [ ] Optional: ETag/304 demo for caching (Phase 1 shows `Cache-Control` and a browser cache hit only).
- [ ] Export this report to PDF into `report/`.

## 7. Final state after testing

- Both DNS servers are running; `app` and `api` → 10.7.17.248; TTL 30.
- Mac 2 runs the Phase 2 nginx config; Mac 3's standby nginx is running as a hot spare.
- pf is **disabled** on Mac 3 and Mac 4 (rolled back); backups remain at `/etc/pf.conf.netforge-backup`.
- Both backends are running.
