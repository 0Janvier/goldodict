#!/bin/bash
# Compile, signe et emballe Goldodict dans un DMG prêt pour la release.
#
# Dépend de make_app.sh (binaire release + signature Developer ID). Le DMG
# porte le schéma de nom des releases GitHub : Goldodict_<version>_aarch64.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${GOLDODICT_SCRATCH:-$HOME/.cache/goldodict-build}"
APP="$SCRATCH/bundle/Goldodict.app"
OUT_DIR="${GOLDODICT_DMG_DIR:-$ROOT}"
SIGN_ID="${GOLDODICT_SIGN_ID:-Developer ID Application: Sztulman Marc (6MTBLVHJ85)}"

"$ROOT/scripts/make_app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ARCH="$(uname -m)"
DMG="$OUT_DIR/Goldodict_${VERSION}_${ARCH}.dmg"

if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "✗ Goldodict.app n'est pas correctement signée, DMG non construit." >&2
    exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/goldodict-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

echo "→ assemblage du DMG ($VERSION, $ARCH)"
ln -s /Applications "$STAGE/Applications"
cp -R "$APP" "$STAGE/Goldodict.app"

mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create \
    -volname "Goldodict $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

echo "→ signature du DMG ($SIGN_ID)"
codesign --force --sign "$SIGN_ID" "$DMG"

echo "✓ $DMG"
echo "  Publication : gh release create v$VERSION \"$DMG\" --title \"Goldodict $VERSION\" --notes-file -"
