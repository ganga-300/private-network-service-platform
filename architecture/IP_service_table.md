# Machine, IP and Service Table

| Mac | Member | Role | IP | Subnet mask | Gateway | MAC address | Service | Port |
|---|---|---|---|---|---|---|---|---|
| Mac 1 | Ganga | Private DNS + test client | 10.7.15.247 | 255.255.224.0 | 10.7.0.1 | 1e:47:db:50:09:1c | dnsmasq | 53 |
| Mac 2 | Alisha | Edge / reverse proxy + load balancer | 10.7.18.238 | 255.255.224.0 | 10.7.0.1 | 7a:19:fc:59:a3:19 | nginx (HTTPS) | 8443 |
| Mac 3 | Pratiti | Backend A | 10.7.19.184 | 255.255.224.0 | 10.7.0.1 | 3a:13:d0:9a:3b:a7 | Python API | 3001 |
| Mac 4 | Anuradha | Backend B + test client | 10.7.13.88 | 255.255.224.0 | 10.7.0.1 | b6:a8:43:7f:97:cd | Python API | 3002 |

Domain: app.netforge.test (resolved by the DNS server on Mac 1 to Mac 2).
Interface: en0 (Wi-Fi). Network: 10.7.0.0/19.

IPs, gateways and MAC addresses verified on 5 Oct 2026. They came from DHCP and have changed before,
so re-verify with `ipconfig getifaddr en0` on each Mac right before submission.