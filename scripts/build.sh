#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/Naada.app"
IDENTITY="Developer ID Application: Jonathan Bahu (BG55CF653X)"
TEAM_ID="BG55CF653X"

cd "$ROOT"

if [[ "$CONFIG" != "release" && "$CONFIG" != "debug" ]]; then
    echo "Usage: scripts/build.sh [release|debug]" >&2
    exit 2
fi

IDENTITIES="$(security find-identity -v -p codesigning)"
if [[ "$IDENTITIES" != *"$IDENTITY"* ]]; then
    echo "Identité de signature introuvable : $IDENTITY" >&2
    echo "Installez le certificat Developer ID Application de l'équipe $TEAM_ID." >&2
    exit 1
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

# Signature Developer ID : exigence désignée stable (identifiant + équipe),
# runtime durci et horodatage sécurisé. Aucune notarisation.
echo "→ Signature Developer ID (runtime durci, horodatage sécurisé)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null
codesign --verify --strict "$APP"

SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE_INFO" != *"TeamIdentifier=$TEAM_ID"* ]]; then
    echo "Échec : l'équipe $TEAM_ID est absente de la signature." >&2
    exit 1
fi
if [[ "$SIGNATURE_INFO" != *"(runtime)"* ]]; then
    echo "Échec : le runtime durci n'est pas activé dans la signature." >&2
    exit 1
fi
if [[ "$SIGNATURE_INFO" != *"Timestamp="* ]]; then
    echo "Échec : l'horodatage sécurisé est absent de la signature." >&2
    exit 1
fi

REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
if ! grep -Fq 'identifier "com.naada.recorder"' <<< "$REQUIREMENT"; then
    echo "Échec : l'exigence désignée ne porte pas l'identifiant du bundle." >&2
    exit 1
fi
if ! grep -Fq "certificate leaf[subject.OU] = $TEAM_ID" <<< "$REQUIREMENT"; then
    echo "Échec : l'exigence désignée ne porte pas l'équipe $TEAM_ID." >&2
    exit 1
fi
if grep -Fq 'cdhash' <<< "$REQUIREMENT"; then
    echo "Échec : l'exigence désignée dépend du CDHash (signature instable)." >&2
    exit 1
fi

echo "✓ $APP"
echo "  Signature : Developer ID Application (équipe $TEAM_ID), runtime durci, horodatage sécurisé"
echo "  Non notarisée : Gatekeeper peut refuser le lancement direct."
echo "  Lancement manuel : open \"$APP\""
