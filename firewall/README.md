# Backend firewall (Phase 2, Extension C: service isolation)

Goal: only the edge (Mac 2, nginx) can reach the backends. Clients must always go through
`https://app.netforge.test:8443`, never straight to `:3001` or `:3002`.

## Method (as advised by our faculty)

We do not replace the macOS ruleset. Our rules live in their own anchor file,
`/etc/pf.anchors/netforge`, which is referenced from `/etc/pf.conf`. Apple's own `com.apple` anchors stay untouched.

| Mac | Anchor file in this repo | Port protected |
|---|---|---|
| Mac 3 (Backend A) | `netforge-mac3.pf` | 3001 |
| Mac 4 (Backend B) | `netforge-mac4.pf` | 3002 |

## Apply

```bash
sudo cp -n /etc/pf.conf /etc/pf.conf.netforge-backup        # rollback copy (-n: never overwrite an existing backup)
sudo cp netforge-macX.pf /etc/pf.anchors/netforge             # X = 3 or 4
grep -q 'anchor "netforge"' /etc/pf.conf || printf '%s\n' 'anchor "netforge"' 'load anchor "netforge" from "/etc/pf.anchors/netforge"' | sudo tee -a /etc/pf.conf
sudo pfctl -vnf /etc/pf.conf                                  # dry run: parse only, load nothing
sudo pfctl -f /etc/pf.conf                                    # load (the "-f could flush rules" warning is expected; the file still contains every Apple anchor)
sudo pfctl -E 2>&1 | tee ~/pf_token.txt                       # enable pf, keep the reference token
sudo pfctl -a netforge -sr                                    # our two rules
sudo pfctl -sr                                                # Apple anchors are still there
```

## Rollback

```bash
sudo pfctl -a netforge -F all                                 # flush our anchor
sudo cp /etc/pf.conf.netforge-backup /etc/pf.conf             # restore the original file
sudo pfctl -f /etc/pf.conf
sudo pfctl -X "$(awk '/Token/{print $NF}' ~/pf_token.txt)"    # release our enable reference
sudo pfctl -s info | head -1                                  # Status: Disabled (as before)
```

## Why "drop" and not "return"

`block drop` sends nothing back, so a blocked client sees a **timeout**. A closed port answers
with a TCP RST, which the client sees as **connection refused**. Telling these two apart is how you
know whether a firewall or a stopped service is the problem (see the real 504 case in
`evidence/13_troubleshooting`).
