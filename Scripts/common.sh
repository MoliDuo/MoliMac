# shellcheck shell=bash
#
# Shared names and version numbers for the build scripts. Source it, don't run it.
#
# The version lives only in the VERSION file at the repository root (MoliSpec 006).
# CFBundleVersion is derived from it: X*1000000 + Y*1000 + Z, so it only ever grows.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="MoliMac"
DISPLAY_NAME="Moli Mac"
BUNDLE_IDENTIFIER="com.moliduo.mac"
MINIMUM_SYSTEM_VERSION="27.0"
REPOSITORY="${GITHUB_REPOSITORY:-MoliDuo/MoliMac}"
FEED_URL="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
# macOS 27 runs only on Apple silicon.
ARCH="arm64"

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
if ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "VERSION 文件不是 X.Y.Z：$VERSION" >&2
    exit 1
fi
BUILD_NUMBER="$((BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3]))"
TAG="v$VERSION"

APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
ASSET_BASE="${APP_NAME}_${VERSION}_macos_${ARCH}"
ZIP_NAME="$ASSET_BASE.zip"
DMG_NAME="$ASSET_BASE.dmg"

PUBLIC_KEY_FILE="$ROOT_DIR/Config/SparklePublicKey.txt"
SIGNING_CERTIFICATE_FILE="$ROOT_DIR/Config/CodeSigningCertificate.txt"

# Deletes a file or directory tree if it exists.
remove_path() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        find "$1" -delete
    fi
}

sparkle_public_key() {
    sed -e 's/#.*$//' "$PUBLIC_KEY_FILE" | tr -d '[:space:]' | head -n 1
}
