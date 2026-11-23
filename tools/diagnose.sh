#!/bin/bash
# NetForge layer-by-layer diagnosis (Phase 2, Extension F).
# Run on any CLIENT Mac:   bash tools/diagnose.sh [name] [port]
# Run on the EDGE (Mac 2): bash tools/diagnose.sh --edge     (also checks the backends directly)
#
# The order is the method: resolver config -> DNS -> IP reachability -> TCP -> TLS -> HTTP.
# The first layer that FAILS is where the fault is. Everything above it cannot work either.

NAME="app.netforge.test"; PORT=8443; EDGE_MODE=0
for a in "$@"; do
  case "$a" in
    --edge) EDGE_MODE=1 ;;
    [0-9]*) PORT="$a" ;;
    *) NAME="$a" ;;
  esac
done
DNS_SERVERS="10.7.15.247 10.7.3.10"            # primary (Mac 1), backup (Mac 4)
BACKENDS="10.7.28.81:3001 10.7.3.10:3002"      # Backend A (Mac 3), Backend B (Mac 4)
CURL=/usr/bin/curl                             # Apple's curl trusts the macOS keychain (where the mkcert CA is)

pass(){ printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail(){ printf "  \033[31mFAIL\033[0m  %s\n" "$1"; }
info(){ printf "        %s\n" "$1"; }
hdr(){ printf "\n\033[1m[%s] %s\033[0m\n" "$1" "$2"; }

echo "NetForge diagnosis  $(date)  host=$(hostname -s)  ip=$(ipconfig getifaddr en0)"
echo "target: https://$NAME:$PORT"

hdr 1 "Resolver config: which DNS servers is this Mac using?"
scutil --dns | awk '/resolver #1/{f=1} f&&/nameserver\[/{print "        "$0} /resolver #2/{exit}'

hdr 2 "DNS: does the name resolve, and do both servers agree?"
IP=$(dig +short +time=2 +tries=1 "$NAME" | grep -E "^[0-9.]+$" | tail -1)
if [ -n "$IP" ]; then pass "$NAME -> $IP (system resolver)"; else fail "$NAME does not resolve (DNS layer)"; fi
for s in $DNS_SERVERS; do
  a=$(dig +short +time=2 +tries=1 "$NAME" @"$s" | grep -E "^[0-9.]+$" | tail -1)
  if [ -n "$a" ]; then info "server $s answers $a"; else info "server $s: no answer (down, or blocked)"; fi
done
if [ -z "$IP" ]; then echo; echo "STOP: fix DNS first (dnsmasq running? client DNS settings? record present?)."; exit 1; fi

hdr 3 "IP: is the host reachable?"
if ping -c2 -t3 "$IP" >/dev/null 2>&1; then pass "ping $IP"; else fail "no ping reply from $IP (host down, asleep, wrong IP, or ICMP blocked)"; fi

hdr 4 "TCP: does port $PORT accept a connection?"
out=$(nc -vz -G 3 "$IP" "$PORT" 2>&1)
if echo "$out" | grep -q succeeded; then pass "TCP $IP:$PORT open"
else
  fail "TCP $IP:$PORT: $(echo "$out" | sed 's/^nc: //')"
  info "'refused' = host up, nothing listening (service stopped / wrong port / wrong IP)"
  info "'timed out' = packets dropped (firewall, host asleep, Wi-Fi)"
  echo; echo "STOP: transport layer. Check the service on $IP, the port, and firewalls."; exit 1
fi

hdr 5 "TLS: handshake, certificate and trust"
tls=$($CURL -sv --max-time 8 -o /dev/null "https://$NAME:$PORT/" 2>&1)
if echo "$tls" | grep -q "SSL certificate verify ok"; then
  pass "certificate trusted and matches $NAME"
  echo "$tls" | grep -E "SSL connection using|subject:|issuer:" | sed 's/^\*/       /'
else
  fail "TLS problem"
  echo "$tls" | grep -iE "ssl|certificate|tls|wrong version|alert" | head -5 | sed 's/^/        /'
  info "'wrong version number' / 'alert protocol version' = the port speaks plain HTTP, not TLS"
  info "'unable to get local issuer' = client does not trust the CA"
  info "'no alternative certificate subject name matches' = wrong certificate for this name"
  echo; echo "STOP: TLS layer."; exit 1
fi

hdr 6 "HTTP: application response through the edge"
for i in 1 2 3 4; do
  r=$($CURL -s -o /dev/null --max-time 8 -w '%{http_code} X-Edge=%header{x-edge} X-Backend=%header{x-backend} %{time_total}s' "https://$NAME:$PORT/api/status")
  code=${r%% *}
  if [ "$code" = "200" ]; then pass "$r"; else fail "$r"; fi
done
info "502 = edge cannot connect to any backend (refused); 504 = edge timed out waiting for backends"
info "only one X-Backend letter = the other backend is down or removed from the upstream"

if [ "$EDGE_MODE" = 1 ]; then
  hdr 7 "Edge -> backends (run on Mac 2)"
  for b in $BACKENDS; do
    c=$($CURL -s -o /dev/null --max-time 4 -w '%{http_code}' "http://$b/api/status")
    if [ "$c" = "200" ]; then pass "backend $b HTTP 200"; else fail "backend $b unreachable (code $c)"; fi
  done
  info "last nginx errors:"; tail -n 3 /opt/homebrew/var/log/nginx/error.log 2>/dev/null | sed 's/^/        /'
fi
echo; echo "Done. First FAIL from the top = the faulty layer."
