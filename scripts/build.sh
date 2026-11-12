#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/Naada.app"

cd "$ROOT"

if [[ "$CONFIG" != "release" && "$CONFIG" != "debug" ]]; then
    echo "Usage: scripts/build.sh [release|debug]" >&2
    exit 2
fi

echo "→ Compilation Swift ($CONFIG)"
swift build -c "$CONFIG" --product Naada
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BINARY="$BIN_DIR/Naada"

if [[ ! -x "$BINARY" ]]; then
    echo "Binaire introuvable : $BINARY" >&2
    exit 1
fi

echo "→ Assemblage de Naada.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$BINARY" "$APP/Contents/MacOS/Naada"
install -m 644 "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
install -m 644 "$ROOT/vendor/shine/COPYING" "$APP/Contents/Resources/Shine-COPYING.txt"
install -m 644 "$ROOT/CREDITS.md" "$APP/Contents/Resources/CREDITS.md"

echo "→ Compilation de l'icône (Icon Composer)"
ICON_SRC="$ROOT/packaging/AppIcon.icon"
if [[ ! -d "$ICON_SRC" ]]; then
    echo "Source d'icône introuvable : $ICON_SRC" >&2
    exit 1
fi
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw -o - "$ROOT/packaging/Info.plist")"
ICON_PARTIAL="$APP/Contents/Resources/AppIcon-partial.plist"
xcrun actool "$ICON_SRC" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target "$MIN_MACOS" \
    --app-icon AppIcon \
    --standalone-icon-behavior all \
    --output-partial-info-plist "$ICON_PARTIAL" \
    --warnings --errors --notices \
    --output-format human-readable-text
rm -f "$ICON_PARTIAL"

for icon_output in Assets.car AppIcon.icns; do
    if [[ ! -f "$APP/Contents/Resources/$icon_output" ]]; then
        echo "Icône compilée introuvable : $icon_output" >&2
        exit 1
    fi
done

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Signature ad hoc locale : aucune identité de développeur, aucun accès réseau.
codesign --force --sign - --timestamp=none "$APP" >/dev/null
codesign --verify --strict "$APP"

echo "✓ $APP"
echo "  Signature : ad hoc (identité locale, pas de notarisation)"
echo "  Lancement manuel : open \"$APP\""
