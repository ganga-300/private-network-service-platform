# Troubleshooting log (Extension F)

Method every time: run `bash tools/diagnose.sh` on a client and read it top-down.
Resolver config → DNS → IP → TCP → TLS → HTTP. The first FAIL is the faulty layer.

| # | Fault (who injected it) | Symptom the client saw | First failing layer | Evidence that pointed there | Fix |
|---|---|---|---|---|---|
| 0 | Real, not planned: both backends left stopped after the 502 test (23 Nov, 19:44) | `504 Gateway Time-out` from nginx/1.31.6 | Application / backend (DNS, TCP, TLS to the edge all fine) | nginx `error.log`: B `Connection refused (61)`, A `Operation timed out (60)`; `nc` to 3002 refused, to 3001 timed out; Mac 3 ping 121 ms | Restarted both backends with `python3 app.py`. A timed out instead of refusing, most likely because of Wi-Fi latency on Mac 3 (not proven). |
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
