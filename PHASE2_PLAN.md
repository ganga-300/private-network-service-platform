# Phase 2 Plan: Harden, Recover, and Troubleshoot

Working plan for NetForge Phase 2. Phase 2 builds on the Phase 1 network. Nothing gets rebuilt.

## Phase 2 gate (from the brief)

Phase 2 is complete when we have demonstrated **backup DNS, TTL behaviour, service isolation, HA failover, and at least one troubleshooting challenge**.

Review 2 marks (50): Ext A+B+D = 15 · Ext C+E = 10 · Ext F = 10 · Final report = 5 · Individual viva = 10.

## Phase 2 roles

Every Mac keeps its Phase 1 job and takes on one extra one.

| Mac | Member | Phase 1 role (unchanged) | New in Phase 2 |
|---|---|---|---|
| Mac 1 | Ganga | Primary DNS (dnsmasq) + test client | TTL = 30 s, record changes for B and E, client for A/B/E tests |
| Mac 2 | Alisha | nginx edge + load balancer | Health-check / failover config (D), shares the TLS cert with the standby edge (E) |
| Mac 3 | Pratiti | Backend A :3001 | **Standby nginx edge** :8443 (E), pf firewall on 3001 (C) |
| Mac 4 | Anuradha | Backend B :3002 + test client | **Backup DNS** (dnsmasq) (A), pf firewall on 3002 (C), main test client |

Why this split:
- **Changed on 23 Nov 2026:** Round 0 showed Mac 3 already runs a standby nginx on 8443 (root, nginx 1.31.9, its own copy of the cert), set up on 22 Nov. We keep it, so the standby edge is Mac 3 and the backup DNS moves to Mac 4. The brief allows either Mac.
- The backup DNS must not be on Mac 1, so it goes on Mac 4.
- The standby edge listens on 8443 and Backend A on 3001, so they don't clash.

## Execution order (rounds)

We run one round at a time. Each member runs their commands and pastes back the output. Claude checks it before we move to the next round.

| Round | What | Who | Risk |
|---|---|---|---|
| 0 | Pre-flight: re-check IPs (DHCP), confirm Phase 1 still works, record versions and paths | All 4 | none |
| 1 | **Ext D**: nginx passive health checks + fast failover. Also fills the Phase 1 failure gaps (both backends down → 502, wrong port, wrong DNS server, wrong record IP) | Mac 2, Mac 3, client | low |
| 2 | **Ext A**: backup dnsmasq on Mac 4; clients list Mac 1 + Mac 4; stop Mac 1 and show resolution continues | Mac 4, Mac 1, Mac 2 | medium (client DNS settings) |
| 3 | **Ext B**: `local-ttl=30`, change a record, watch the client cache keep the old answer until the TTL expires, then flush | Mac 1, Mac 4 | low |
| 4 | **Ext C**: pf rules on Mac 3/Mac 4 so only Mac 2 can reach 3001/3002; prove it; **roll back** | Mac 3, Mac 4, Mac 2, Mac 1 | medium (firewall) |
| 5 | **Ext E**: standby nginx on Mac 3 with the same cert; DNS cutover to Mac 3; show cached vs fresh clients; roll back | Mac 2, Mac 3, Mac 1, Mac 4 | medium |
| 6 | **Ext F** practice: `diagnose.sh` layer-by-layer runbook + team-injected fault drills | All | none |
| 7 | Deliverables: Phase 2 report, updated architecture doc, config bundle, evidence folders | All | none |

C runs before E on purpose. While the firewall is on, only Mac 2 may reach the backends, so the standby edge on Mac 3 couldn't reach Backend B. We demo C, roll it back (the brief requires that anyway), then do E.

## Extension details

### Ext D: HA failover (Mac 2)
- Upstream: `server <A>:3001 max_fails=1 fail_timeout=10s;` (same for B).
- `proxy_next_upstream error timeout http_502 http_503 http_504;` with `proxy_next_upstream_tries 2`.
- `proxy_connect_timeout 2s;` so a backend whose machine is completely off (no TCP RST) is skipped in about 2 s, not the default 60 s.
- Add `add_header X-Edge primary-mac2 always;` so E can show which edge answered.
- Demo: 10 requests show A/B → stop Backend A → 10 requests are all B with HTTP 200 → start A → A/B again.
- Explain: this is *passive* health checking (open-source nginx). Active checks are in nginx Plus/HAProxy. The remaining single point of failure is the edge itself (Mac 2). Fixes: a second edge plus DNS failover (E), or a floating VIP with keepalived/VRRP, or anycast. In the cloud, a managed ALB is itself multi-AZ.

### Ext A: backup DNS (Mac 4)
- Same records as Mac 1. Listens on `127.0.0.1` and Mac 4's IP.
- Clients: `sudo networksetup -setdnsservers Wi-Fi <Mac1> <Mac4>` on the client Macs.
- Demo: `dig app.netforge.test` (SERVER = Mac 1) → `sudo brew services stop dnsmasq` on Mac 1 → `dig app.netforge.test` shows the error for Mac 1, then an answer from Mac 4 → `curl https://app.netforge.test:8443/api/status` still works.
- Contrast: stop both backends instead. DNS still resolves and TLS still works, but you get a 502. A DNS failure means the name doesn't resolve. An app failure means the name resolves but the service is down.

### Ext B: TTL (Mac 1 + Mac 4)
- Phase 1 TTL was **0** (dnsmasq default for local records), so clients never cached. Set `local-ttl=30` on both DNS servers.
- `dig` skips the macOS cache, so it always shows the server's current answer. `dscacheutil -q host` and `curl` go through mDNSResponder, so they show the *cached* answer. Comparing the two is the demo.
- Change the record on **both** DNS servers. Otherwise the client may get a different answer depending on which server it asks.
- Flush: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

### Ext C: service isolation (Mac 3 + Mac 4)
- **Faculty guidance (Kuldeep Kumar Jha):** don't touch the main ruleset. Put our rules in their own file under `/etc/pf.anchors/`, then reference it from `/etc/pf.conf`. The system's Apple rules stay intact.
  1. `sudo cp /etc/pf.conf /etc/pf.conf.netforge-backup` (rollback copy; also saved to `firewall/` in the repo)
  2. Write the rules to `/etc/pf.anchors/netforge`.
  3. Add two lines to the **end** of `/etc/pf.conf`: `anchor "netforge"` and `load anchor "netforge" from "/etc/pf.anchors/netforge"`. All the existing `com.apple` lines stay as they are.
  4. `sudo pfctl -vnf /etc/pf.conf` is a dry run: it checks syntax and loads nothing. Only continue if it prints no errors.
  5. `sudo pfctl -f /etc/pf.conf` then `sudo pfctl -E`. macOS will warn that `-f` "could result in flushing of rules…". That warning appears on every `-f`. It's harmless here, because the file we load *is* the system file and still contains every Apple anchor.
  6. Verify: `sudo pfctl -a netforge -sr` shows only our rules. `sudo pfctl -sr` still shows the `com.apple` anchors.
  7. Rollback: `sudo cp /etc/pf.conf.netforge-backup /etc/pf.conf && sudo pfctl -f /etc/pf.conf`, then `sudo pfctl -X <token>` with the token that `-E` printed.
- The rules only touch TCP to 3001 (or 3002). Wi-Fi, DHCP, DNS and everything else are never matched, so connectivity isn't at risk. Keep a second terminal open during the demo in case a rollback is needed.
- Rules: `pass in quick` TCP from Mac 2 to the port, then `block drop in quick` TCP to the port from anyone else.
- Demo: from Mac 2 `curl` the backend directly → works. From Mac 1/Mac 4 `curl --connect-timeout 5` → times out. `https://app.netforge.test:8443` still works.
- Rollback: flush the anchor, release the pf enable token, show direct access works again.
- Explain drop vs return: a timeout means a firewall. "Connection refused" means a closed port. That distinction helps in Ext F.

### Ext E: edge migration (Mac 4 + Mac 2 + Mac 1)
- Mac 3: nginx is already installed and running on 8443 as root, and has a copy of the cert in `~/netforge-certs`. Before the cutover we align its config with Mac 2's Phase 2 config (with `X-Edge: standby-mac3`), and compare SHA-256 fingerprints to confirm its cert is the same one Mac 2 uses (signed by the mkcert CA the clients trust). Do **not** run `mkcert` on Mac 3, because that would create a new, untrusted CA.
- Before the cutover: on Mac 1, warm the cache (`curl` once). On Mac 4 or Mac 1, loop `curl -s -o /dev/null -w '%{remote_ip} %header{x-edge}\n'`.
- Cutover: point `app.netforge.test` to Mac 4 on both DNS servers. The cached client keeps hitting Mac 2 for up to 30 s, then switches. A client that has just flushed switches immediately.
- Roll the record back to Mac 2 afterwards.

### Ext F: troubleshooting (all)
- Write `tools/diagnose.sh`. It checks in order: resolver config → `dig` → `ping` → `nc -vz <edge> 8443` → `openssl s_client -servername` → `curl -v` → direct backend checks from Mac 2.
- Drills (one member breaks it, the others diagnose): dnsmasq stopped; wrong record IP; client DNS set to 8.8.8.8; nginx stopped; wrong upstream port; `server_name`/cert mismatch; pf blocking 8443; both backends down; CA removed from a client keychain.

## Phase 1 gaps found in the repo (fix during Phase 2)

- `architecture/architecture.md` is **empty** (0 bytes), even though commit 33b2c84 says it was written. `backend-a/README.md` is also empty.
- `evidence/07_failure` only has "one backend stopped". The brief also wants: wrong DNS server, wrong record IP, both backends down (502), wrong destination port. We capture these in Round 1.
- Caching: `Cache-Control` is shown, but no `304 Not Modified`. Optional fix: add an ETag + conditional response in both Flask apps.

## Screenshot checklist (take once, name exactly like this)

Rules for every screenshot:
- Run `date` first and keep the prompt visible, so each shot shows **which Mac** and **what time**. The time matters for TTL and failover.
- Make the Terminal font big (Cmd +) and capture just the window: Cmd+Shift+4, then Space, then click the window.
- Whoever takes a shot AirDrops it to Ganga, who commits it to the exact path below.
- Tick the box when the file is in the repo.

### Round 0/1: LAN check (after the IPs are fixed) → `evidence/00_lan/`
- [ ] `01_mac1_ip_ping.png` (Mac 1): own IP + ping to the other three
- [ ] `02_mac2_ip_ping.png` (Mac 2)
- [ ] `03_mac3_ip_ping.png` (Mac 3)
- [ ] `04_mac4_ip_ping.png` (Mac 4)

### Round 1: Ext D HA failover → `evidence/11_ha_failover/`
- [x] `01_nginx_phase2_config.png` (Mac 2): upstream with `max_fails`/`fail_timeout`, `proxy_next_upstream`, `nginx -t` OK
- [x] `02_both_backends_A_B.png` (Mac 4 client): 10 requests alternating A/B
- [x] `03_backendA_stopped.png` (Mac 3): Backend A stopped (Ctrl+C visible)
- [x] `04_all_requests_B_200.png` (Mac 4 client): 10 requests, all B, all 200
- [x] `04b_edge_log_failover.png` (Mac 2): `netforge_upstream.log` shows the retry from A to B
- [x] `05_backendA_restarted_A_B.png` (Mac 4 client): A/B alternating again

### Round 1: Phase 1 failure gaps → `evidence/07_failure/`
- [x] `04_wrong_dns_server.png` (client): DNS set to 8.8.8.8 → `dig` fails, `ping <Mac2 IP>` works
- [x] `05_wrong_record_ip.png` (Mac 1 + client): record points to a wrong IP → `dig` succeeds, `curl` fails
- [x] `06_both_backends_502.png` (client): both backends stopped → `curl -v` shows TLS OK + `502 Bad Gateway`
- [x] `07_wrong_port.png` (client): `ping` works, `curl https://app.netforge.test:9443` → connection refused

### Round 2: Ext A backup DNS → `evidence/08_backup_dns/`
- [ ] `01_backup_dnsmasq_mac4.png` (Mac 4): dnsmasq running, `dig @<Mac4> app.netforge.test` answers
- [ ] `02_client_two_dns_servers.png` (Mac 2 as client): `scutil --dns` lists Mac 1 and Mac 4
- [x] (covered by `05b`) `03_answer_from_primary.png` (Mac 2): `dig` → SERVER = Mac 1
- [ ] `04_primary_stopped.png` (Mac 1): `sudo brew services stop dnsmasq`
- [x] (covered by `05b_backup_dns_curl_200.png`) `05_answer_from_backup.png` (Mac 2): `dig` → SERVER = Mac 4 + `curl` still 200
- [x] `06_dns_vs_app_failure.png` (Mac 2): DNS OK but both backends down = 502, compared with DNS down = name not resolved
- [x] `07_primary_restored.png` (Mac 2): primary back, SERVER = Mac 1, HTTP 200
- [x] real fault found: `13_troubleshooting/drill_00_real_504_mac{2,3,4}.png` (both backends left stopped → 504; B refused, A timed out)
- [ ] optional: `dns_failover.pcapng` (Wireshark on Mac 2): query to Mac 1 fails, retry goes to Mac 4

### Round 3: Ext B TTL → `evidence/09_dns_ttl/`
- [x] (in 03_cached_vs_server_timeline / 05) `01_ttl_30.png` (client): `dig` shows TTL 30 in the ANSWER section
- [x] `02_record_changed_mac1.png` (was 02_record_changed_on_server) (Mac 1): config edited + `dig @<Mac1>` shows the new IP right away
- [x] (in 03_cached_vs_server_timeline / 05) `03_client_still_cached_old.png` (client): `dscacheutil -q host` still shows the old IP (with `date`)
- [x] (in 03_cached_vs_server_timeline / 05) `04_after_ttl_new_ip.png` (client): about 30 s later it shows the new IP (with `date`)
- [x] (in 03_cached_vs_server_timeline / 05) `05_flush_immediate.png` (client): flush cache → new answer immediately

### Round 4: Ext C service isolation → `evidence/10_service_isolation/`
Run this on both Mac 3 and Mac 4. Name the files `_mac3` / `_mac4`.
- [x] `01_pf_backup_and_anchor_file_mac3`: `ls -l /etc/pf.conf*` + `cat /etc/pf.anchors/netforge`
- [x] `02_pf_dry_run_ok_mac3`: `sudo pfctl -vnf /etc/pf.conf` with no errors
- [x] `03_pf_rules_loaded_mac3`: `sudo pfctl -a netforge -sr` + `sudo pfctl -sr` still shows com.apple
- [x] `04_edge_can_reach_backends` (Mac 2): direct `curl` to :3001 and :3002 → 200
- [x] `05_client_blocked` (Mac 1 or Mac 4): direct `curl` to :3001/:3002 → timeout
- [x] `06_https_still_works` (client): `https://app.netforge.test:8443` still serves A/B
- [x] `07_rollback_restored_mac3`: backup restored, direct access works again

### Round 5: Ext E edge migration → `evidence/12_edge_migration/`
- [x] `01_standby_nginx_mac3` + `01b_standby_direct_test` (Mac 3): `nginx -t` OK + listening on 8443 + cert fingerprint matches Mac 2
- [ ] `02_before_cutover_primary.png` (client): `X-Edge: primary-mac2`
- [x] `03_dns_record_changed` (Mac 1 + Mac 4): record now points to Mac 3
- [x] `04_cached_client_old_edge` (cached client): still `primary-mac2` for up to 30 s
- [x] `05_fresh_client_new_edge` (flushed client): `standby-mac3` immediately
- [x] `06_after_ttl_all_standby` (both clients): all `standby-mac3`
- [x] `07_rollback_to_primary`: record back to Mac 2

### Round 6: Ext F troubleshooting → `evidence/13_troubleshooting/`
- [ ] `drill_01_<fault>.png`, `drill_02_<fault>.png`, … `diagnose.sh` output for each practice fault
- [ ] `notes.md`: fault, symptom, layer, how it was found, fix (one row per drill; this feeds the final report)

### Phase 2 configs (no screenshots; files go in the repo)
`dns/dnsmasq.conf` (updated) · `dns/dnsmasq-backup.conf` · `nginx/nginx-phase2.conf` · `nginx/nginx-standby.conf` · `firewall/netforge.pf` · `firewall/pf.conf.backup` · `firewall/README.md` · `tools/diagnose.sh`

New config bundle files: `dns/dnsmasq-backup.conf`, `nginx/nginx-phase2.conf`, `nginx/nginx-standby.conf`, `firewall/netforge.pf` + `firewall/README.md` (apply/rollback), `tools/diagnose.sh`.

## Final deliverables checklist (Review 2)

- [ ] Architecture doc updated (Phase 2 topology: backup DNS, standby edge, firewall boundary)
- [ ] Config bundle: Phase 2 dnsmasq ×2, nginx Phase 2 + standby, firewall rules + rollback, TLS notes on sharing the cert
- [ ] Evidence folders 07–13 filled
- [ ] Phase 2 final report: what changed from Phase 1 · test results table · troubleshooting findings · one learning paragraph per extension (A–F)
- [ ] Rehearse the 11-step demo sequence (Section 8) end to end
- [ ] Every member can explain every extension (viva)
