# TLS Setup

TLS is terminated at the nginx edge (Mac 2) on port 8443.

## Certificate creation (mkcert, local CA)

    mkcert -install
    mkcert app.netforge.test

This creates a local certificate authority and a server certificate for
app.netforge.test. The hostname is stored in the Subject Alternative Name (SAN),
which must match the name in the URL or clients reject the certificate.

Files are kept outside the repo, in ~/netforge-certs:
- app.netforge.test.pem       (certificate, public)
- app.netforge.test-key.pem   (private key, NEVER committed)

## nginx configuration

    listen 8443 ssl;
    ssl_certificate     <path>/app.netforge.test.pem;
    ssl_certificate_key <path>/app.netforge.test-key.pem;

## Trusting the CA on client Macs

Only the public CA file (rootCA.pem) is shared. The CA private key
(rootCA-key.pem) is never shared or committed.

    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain rootCA.pem

After this, curl and browsers accept the certificate with no -k flag.

## TLS handshake

curl reported TLS 1.3, "SSL certificate verify ok" and a SAN match for
app.netforge.test. In Wireshark, TLS 1.3 shows Client Hello, Server Hello,
then encrypted handshake data and Application Data.
