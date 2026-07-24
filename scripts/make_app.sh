#!/bin/bash
# Fabrique Abracadabra.app à partir du binaire SwiftPM, le signe avec l'identité
# Developer ID, puis l'installe dans /Applications.
#
# La signature avec une identité STABLE est indispensable : une signature ad hoc
# change d'empreinte à chaque compilation, ce qui fait perdre à l'application ses
# autorisations micro et Accessibilité à chaque rebuild.
#
# La compilation se fait hors de ~/Documents : iCloud évince le contenu de .build
# et produit des lectures tronquées en plein build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${ABRACADABRA_SCRATCH:-$HOME/.cache/abracadabra-build}"
# Le bundle est assemblé et signé HORS de ~/Documents : fileproviderd y repose
# com.apple.FinderInfo et com.apple.fileprovider.fpfs#P instantanément, et
# codesign refuse tout bundle porteur de ces attributs. Un xattr -cr ne suffit
# pas, les attributs réapparaissent avant la signature.
APP="$SCRATCH/bundle/Abracadabra.app"
SIGN_ID="${ABRACADABRA_SIGN_ID:-Developer ID Application: Sztulman Marc (6MTBLVHJ85)}"

echo "→ swift build -c release (scratch : $SCRATCH)"
cd "$ROOT"
swift build -c release --scratch-path "$SCRATCH"

BIN="$SCRATCH/release/Abracadabra"
if [[ ! -x "$BIN" ]]; then
    echo "✗ binaire introuvable : $BIN" >&2
    exit 1
fi

echo "→ assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Abracadabra"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/lexique.default.json" ]] && \
    cp "$ROOT/Resources/lexique.default.json" "$APP/Contents/Resources/"
[[ -d "$ROOT/sidecar" ]] && cp -R "$ROOT/sidecar" "$APP/Contents/Resources/sidecar"

echo "→ purge des attributs étendus"
xattr -cr "$APP"

echo "→ signature ($SIGN_ID)"
if ! security find-identity -v -p codesigning | grep -qF "$SIGN_ID"; then
    echo "✗ identité de signature absente du trousseau : $SIGN_ID" >&2
    echo "  Surcharger avec ABRACADABRA_SIGN_ID=… ou '-' pour une signature ad hoc." >&2
    exit 1
fi
codesign --force --options runtime \
    --entitlements "$ROOT/Resources/Abracadabra.entitlements" \
    --sign "$SIGN_ID" "$APP"
codesign --verify --verbose=2 "$APP"

echo "→ installation dans /Applications"
if pgrep -x Abracadabra >/dev/null; then
    echo "  (arrêt de l'instance en cours)"
    pkill -x Abracadabra || true
    sleep 1
fi
rm -rf "/Applications/Abracadabra.app"
cp -R "$APP" "/Applications/Abracadabra.app"
xattr -dr com.apple.quarantine "/Applications/Abracadabra.app" 2>/dev/null || true

echo "✓ /Applications/Abracadabra.app prêt."
echo "  Premier lancement : autoriser le Microphone, puis l'Accessibilité"
echo "  (Réglages Système > Confidentialité et sécurité)."
