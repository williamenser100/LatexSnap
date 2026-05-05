#!/bin/bash
# One-time setup: creates a stable self-signed code-signing certificate.
# Run this once. After it completes, use build.sh for all future builds.

set -e

CERT_NAME="LatexSnap Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
    echo "✓ Certificate '$CERT_NAME' already exists — nothing to do."
    exit 0
fi

echo "Creating self-signed code-signing certificate '$CERT_NAME'..."

# OpenSSL config with the codesigning extended key usage
cat > /tmp/ls_cert.conf << 'EOF'
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[dn]
CN = LatexSnap Dev

[ext]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = codeSigning
subjectKeyIdentifier   = hash
EOF

# Generate key + certificate
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -config /tmp/ls_cert.conf \
    -keyout /tmp/ls_key.pem \
    -out    /tmp/ls_cert.pem 2>/dev/null

# Bundle as PKCS#12
openssl pkcs12 -legacy -export \
    -out     /tmp/ls.p12 \
    -inkey   /tmp/ls_key.pem \
    -in      /tmp/ls_cert.pem \
    -passout pass:latexsnap 2>/dev/null

# Import private key + cert into the login keychain
# -T /usr/bin/codesign  → pre-authorises codesign to use the key
security import /tmp/ls.p12 \
    -k "$KEYCHAIN" \
    -P latexsnap \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Remove the passphrase requirement so codesign never prompts
# (requires the login keychain password — macOS may show a dialog once)
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN" 2>/dev/null || \
    echo "  Note: if codesign prompts for keychain access, click 'Always Allow'."

rm -f /tmp/ls_key.pem /tmp/ls_cert.pem /tmp/ls.p12 /tmp/ls_cert.conf

echo ""
echo "✓ Certificate '$CERT_NAME' installed."
echo "  Run ./build.sh to build, sign, and deploy the app."
