#!/usr/bin/env bash
#
# One-time setup of a development signing certificate on a developer's Mac.
#
# Ad-hoc signed builds get a new identity on every build, so macOS forgets the
# Accessibility grant each time. Signing local builds with one fixed certificate
# keeps the grant. The certificate is for local builds only; releases are signed
# with the shared certificate in CI.
#
# Everything lives in ~/.moli-dev-signing (mode 700): a standalone keychain file
# that is not added to the keychain search list, its random password, and the
# certificate fingerprint. Nothing goes into the login or system keychain, and
# nothing goes into the repository. Delete the folder to undo.

set -euo pipefail

DIR="$HOME/.moli-dev-signing"
KEYCHAIN="$DIR/dev.keychain-db"
COMMON_NAME="Moli Development Code Signing"
OPENSSL=/usr/bin/openssl

if [ -e "$DIR" ]; then
    echo "$DIR 已经存在。要重建先删掉它（之后要重新授权一次辅助功能）。" >&2
    exit 1
fi

umask 077
mkdir -p "$DIR"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/cert.cnf" <<CONFIG_EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $COMMON_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG_EOF

"$OPENSSL" req -new -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK_DIR/cert.cnf" \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" 2> /dev/null
P12_PASSWORD="$("$OPENSSL" rand -hex 24)"
"$OPENSSL" pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" -name "$COMMON_NAME" \
    -passout "pass:$P12_PASSWORD" -out "$WORK_DIR/dev.p12"

KEYCHAIN_PASSWORD="$("$OPENSSL" rand -hex 24)"
printf '%s\n' "$KEYCHAIN_PASSWORD" > "$DIR/keychain-password"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# No auto-lock; build-app.sh unlocks it with the password file anyway.
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK_DIR/dev.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null

"$OPENSSL" x509 -in "$WORK_DIR/cert.pem" -noout -fingerprint -sha1 \
    | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]' > "$DIR/identity"

echo "已建好开发签名：${DIR}（指纹 $(cat "$DIR/identity")）"
echo "之后 Scripts/build-app.sh 会自动用它签名本地构建。"
