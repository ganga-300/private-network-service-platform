# Troubleshooting log (Extension F)

Method every time: run `bash tools/diagnose.sh` on a client and read it top-down.
Resolver config → DNS → IP → TCP → TLS → HTTP. The first FAIL is the faulty layer.

| # | Fault (who injected it) | Symptom the client saw | First failing layer | Evidence that pointed there | Fix |
|---|---|---|---|---|---|
| 0 | Real, not planned: both backends left stopped after the 502 test (23 Nov, 19:44) | `504 Gateway Time-out` from nginx/1.31.6 | Application / backend (DNS, TCP, TLS to the edge all fine) | nginx `error.log`: B `Connection refused (61)`, A `Operation timed out (60)`; `nc` to 3002 refused, to 3001 timed out; Mac 3 ping 121 ms | Restarted both backends with `python3 app.py`. A timed out instead of refusing, most likely because of Wi-Fi latency on Mac 3 (not proven). |
| 1 | dnsmasq stopped on both DNS servers (Mac 1 + Mac 4) | Name cannot be resolved | **DNS** (layer 2) | `drill_01_dns_down.png`: neither 10.7.15.247 nor 10.7.3.10 answers; the script stops before IP/TCP. The cache was flushed first; otherwise the 30 s cached answer would have hidden the fault. | `sudo brew services start dnsmasq` on Mac 1 and Mac 4 |
| 2 | nginx stopped on the edge (Mac 2) | Connection refused on https://app.netforge.test:8443 | **TCP / transport** (layer 4) | `drill_02_tcp_nginx_down.png`: DNS OK (both servers agree), ping OK, `connectx ... 8443 failed: Connection refused`, meaning the host is up but nothing is listening | `brew services start nginx` on Mac 2 |
| 3 | `ssl` removed from `listen 8443` on Mac 2 (port speaks plain HTTP) | TLS handshake fails | **TLS** (layer 5) | `drill_03_tls_no_ssl.png`: TCP 8443 is open and the ClientHello is sent, then `LibreSSL ... tlsv1 alert protocol version`: the server did not reply with TLS | Put `ssl` back on the listen line and restart nginx |
| 4 | Upstream ports changed to 3009/3008 in Mac 2's nginx.conf | `502 Bad Gateway`, `X-Edge: primary-mac2`, no `X-Backend` | **Application / upstream** (layer 6). DNS, TCP and TLS to the edge all pass. | Client: `drill_04_app_wrong_upstream_client.png` (4 x 502). Edge: `drill_04_app_wrong_upstream_edge.png`: the config shows `:3009`/`:3008` and `error.log` says `no live upstreams`. After the first refused attempts, `max_fails=1` marked both backends down for 10 s. | Restore ports 3001/3002 and restart nginx |
