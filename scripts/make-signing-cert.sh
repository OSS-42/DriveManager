#!/bin/sh
# Creates a code signing certificate named "DriveManager Local Signing" in
# your login keychain, once. make-app.sh signs with it, which gives every
# build the same identity, so macOS keeps Full Disk Access after a rebuild.
# No Apple developer account is needed; the certificate is trusted on this
# Mac only. macOS asks for your password to trust it.
set -eu

name="DriveManager Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
    echo "\"$name\" already exists."
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.conf" <<CONF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

# macOS's own openssl (LibreSSL) writes a .p12 that the keychain can import.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$work/cert.conf" -extensions ext \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -name "$name" -passout pass:drivemanager -out "$work/cert.p12"

security import "$work/cert.p12" -k "$keychain" -P drivemanager -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work/cert.pem"

echo "Created \"$name\". Rebuild with ./scripts/make-app.sh --install, then grant Full Disk Access once more; it will stick from now on."
