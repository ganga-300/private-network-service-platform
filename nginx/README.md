# nginx Edge (Reverse Proxy + Load Balancer)

Runs on Mac 2 (Alisha). It is the single entry point for clients.

## What it does
- Terminates TLS on port 8443 for app.netforge.test
- Forwards requests to Backend A (port 3001) and Backend B (port 3002)
- Load balancing: round-robin, the default for an upstream block
- Adds the header Cache-Control: public, max-age=60

## Config
See nginx.conf in this folder. The certificate and key paths point to files
outside the repo. Private keys are never committed.

## Commands
    nginx -t                      # test the config
    brew services restart nginx   # apply changes

## Why the client never sees the backend IPs
The client connects only to the edge. nginx opens a separate TCP connection
to the chosen backend and relays the response back.

## Phase 2

| File | Machine | Purpose |
|---|---|---|
| `nginx.conf` | Mac 2 | Phase 1 config (kept for comparison) |
| `nginx-phase2.conf` | Mac 2 | Live config: passive health checks, failover, `X-Edge: primary-mac2`, upstream log |
| `nginx-standby.conf` | Mac 3 | Standby edge for the DNS cutover (Extension E), `X-Edge: standby-mac3` |

### Health checks and failover (Extension D)
- `max_fails=1 fail_timeout=10s`: one failed connection marks a backend down for 10 s.
- `proxy_next_upstream error timeout http_502 http_503 http_504` + `proxy_next_upstream_tries 2`: retry the request on the other backend.
- `proxy_connect_timeout 2s`: a powered-off machine never sends a RST, so don't wait the default 60 s.
- Upstream log: `tail -f /opt/homebrew/var/log/nginx/netforge_upstream.log` shows `upstream=A, B upstream_status=502, 200` when a retry happens.
- Both backends down: **502** if they refuse the connection, **504** if they time out.

### Standby edge on Mac 3 (Extension E)
It uses the **same** certificate and key as Mac 2 (SHA-256 fingerprint `7E:2E:AB:…:A9:C8`, signed by Alisha's mkcert CA). Never run `mkcert` on another Mac.
It runs as root because its files are root-owned:

```bash
sudo nginx -t -c /opt/homebrew/etc/nginx/netforge-standby.conf
sudo nginx -c /opt/homebrew/etc/nginx/netforge-standby.conf          # start
sudo nginx -s quit -c /opt/homebrew/etc/nginx/netforge-standby.conf  # stop
```

### Remaining single point of failure
If Mac 2 fails, recovery needs a DNS cutover to Mac 3, which takes up to one TTL (30 s) for cached clients.
Removing that wait would need a floating IP shared by both edges (keepalived/VRRP), or a managed load balancer.
