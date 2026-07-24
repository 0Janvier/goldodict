#!/bin/bash
# Construit Resources/AppIcon.icns à partir de design/goldodict-icon.svg.
#
# Le rendu passe par rsvg-convert : chaque taille est tracée depuis le vectoriel
# plutôt que rééchantillonnée depuis la plus grande, sans quoi les arcs de la
# bouche se brouillent en dessous de 64 px.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/design/goldodict-icon.svg"
SMALL="$ROOT/design/goldodict-icon-small.svg"
OUT="$ROOT/Resources/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert absent (brew install librsvg)"; exit 1; }

# L'iconset est monté hors du projet : sous ~/Documents, iCloud pose des attributs
# étendus sur chaque fichier créé et iconutil échoue à la lecture.
WORK="$(mktemp -d /tmp/goldodict-icon.XXXXXX)"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
trap 'rm -rf "$WORK"' EXIT

render() { # source, taille, nom
  rsvg-convert -w "$2" -h "$2" "$1" -o "$SET/$3"
}

# Sous 48 px, la déclinaison simplifiée prend le relais : les arcs de son y sont
# retirés, sans quoi ils se referment sur la bouche et l'icône devient une tache.
source_for() { # taille rendue
  if (( $1 < 48 )); then echo "$SMALL"; else echo "$SVG"; fi
}

for size in 16 32 128 256 512; do
  render "$(source_for "$size")" "$size" "icon_${size}x${size}.png"
  render "$(source_for "$((size * 2))")" "$((size * 2))" "icon_${size}x${size}@2x.png"
done

iconutil --convert icns --output "$OUT" "$SET"
echo "icône : $OUT ($(du -h "$OUT" | cut -f1))"
