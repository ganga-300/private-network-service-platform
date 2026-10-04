#!/bin/bash
# Creates a local CA and a certificate for app.netforge.test using mkcert.
# Keys are written to ~/netforge-certs and are never committed.
mkdir -p ~/netforge-certs && cd ~/netforge-certs
mkcert -install
mkcert app.netforge.test
