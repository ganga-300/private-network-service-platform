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
