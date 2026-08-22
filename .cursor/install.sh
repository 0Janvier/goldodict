#!/usr/bin/env bash
# Prépare une machine Linux (Ubuntu) pour compiler et tester GoldodictCore.
#
# L'application Goldodict elle-même est macOS (AppKit, Speech, SwiftUI) et ne se
# construit pas ici : Package.swift n'inclut la cible exécutable que sur macOS.
# Sur Linux, seule la logique pure et testable de GoldodictCore est compilée,
# exactement la séparation prévue par l'architecture du projet.
#
# Le script est idempotent : il peut être relancé sans effet de bord.
set -euo pipefail

SWIFT_VERSION="6.1.2"
export SWIFTLY_HOME_DIR="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
export SWIFTLY_BIN_DIR="${SWIFTLY_BIN_DIR:-$HOME/.local/bin}"
export PATH="$SWIFTLY_BIN_DIR:$PATH"

echo "→ Dépendances système du runtime Swift"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq \
    gnupg2 libcurl4-openssl-dev libpython3-dev libxml2-dev libncurses-dev libz3-dev

echo "→ swiftly"
if ! command -v swiftly >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" \
        -o "$tmp/swiftly.tar.gz"
    tar -xzf "$tmp/swiftly.tar.gz" -C "$tmp"
    "$tmp/swiftly" init --quiet-shell-followup --assume-yes --skip-install
    rm -rf "$tmp"
fi

# shellcheck disable=SC1091
. "$SWIFTLY_HOME_DIR/env.sh"

echo "→ Toolchain Swift $SWIFT_VERSION"
if ! swiftly list 2>/dev/null | grep -q "$SWIFT_VERSION"; then
    swiftly install "$SWIFT_VERSION" --assume-yes
fi
swiftly use --global-default --assume-yes "$SWIFT_VERSION" >/dev/null 2>&1 || true

swift --version

echo "→ Compilation de GoldodictCore (préchauffe du toolchain)"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift build --target GoldodictCore

echo "✓ Environnement prêt. Lancez la suite avec : swift test"
