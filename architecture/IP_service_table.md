# Machine, IP and Service Table

| Mac | Member | Role | IP | Subnet mask | Gateway | MAC address | Service | Port |
|---|---|---|---|---|---|---|---|---|
| Mac 1 | Ganga | Private DNS + test client | 10.7.15.247 | 255.255.224.0 | 10.7.0.1 | 1e:47:db:50:09:1c | dnsmasq | 53 |
| Mac 2 | Alisha | Edge / reverse proxy + load balancer | 10.7.17.248 | 255.255.224.0 | 10.7.0.1 | 7a:19:fc:59:a3:19 | nginx (HTTPS) | 8443 |
| Mac 3 | Pratiti | Backend A | 10.7.28.81 | 255.255.224.0 | 10.7.0.1 | 3a:13:d0:9a:3b:a7 | Python API | 3001 |
| Mac 4 | Anuradha | Backend B + test client | 10.7.3.10 | 255.255.224.0 | 10.7.0.1 | b2:ba:16:33:57:a5 | Python API | 3002 |

Domain: app.netforge.test (resolved by the DNS server on Mac 1 to Mac 2).
Interface: en0 (Wi-Fi). Network: 10.7.0.0/19.

IPs re-verified on 23 Nov 2026 (Phase 2 start; Mac 2, 3 and 4 had new DHCP leases). They come from DHCP and have
changed before, so re-check them with `ipconfig getifaddr en0` on each Mac right before the evaluation.

Gateway from 5 Oct 2026. All four MAC addresses confirmed on 23 Nov 2026: Mac 1, Mac 2 and Mac 4 from the Wireshark capture
(`evidence/05_wireshark/phase2_full_flow.pcap`), Mac 3 with `ifconfig en0`. macOS can rotate Wi-Fi MAC addresses,
so re-check with `ifconfig en0 | grep ether` before the evaluation.
