#!/bin/zsh
# Construit (sauf --no-build) puis empaquette Naada.app dans dist/Naada.dmg.
# Le contenu du volume se limite à Naada.app et à un lien vers /Applications.
# Aucune notarisation, aucun envoi à Apple.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Naada.app"
DIST="$ROOT/dist"
DMG="$DIST/Naada.dmg"
VOLUME_NAME="Naada"
TEAM_ID="BG55CF653X"

BUILD=1
for argument in "$@"; do
    case "$argument" in
        --no-build) BUILD=0 ;;
        --help|-h)
            echo "Usage: scripts/dmg.sh [--no-build]"
            echo "  --no-build  empaquette le Naada.app existant sans le reconstruire"
            exit 0
            ;;
        *)
            echo "Usage: scripts/dmg.sh [--no-build]" >&2
            exit 2
            ;;
    esac
done

if (( BUILD )); then
    "$ROOT/scripts/build.sh"
else
    echo "→ Empaquetage sans reconstruction (--no-build)"
    if pgrep -x Naada >/dev/null 2>&1; then
        echo "  Naada tourne : le bundle empaqueté est celui déjà construit sur le disque." >&2
    fi
fi

if [[ ! -d "$APP" ]]; then
    echo "Bundle introuvable : $APP" >&2
    echo "Lancez ./scripts/build.sh ou retirez --no-build." >&2
    exit 1
fi

echo "→ Vérification de la signature du bundle"
codesign --verify --strict "$APP"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE_INFO" != *"TeamIdentifier=$TEAM_ID"* ]]; then
    echo "Échec : l'équipe $TEAM_ID est absente de la signature." >&2
    exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/naada-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

echo "→ Préparation du volume $VOLUME_NAME"
ditto "$APP" "$STAGE/Naada.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
rm -f "$DMG"

echo "→ Création de $DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "✓ $DMG ($SIZE)"
echo "  Signature : Developer ID Application (équipe $TEAM_ID)"
echo "  Non notarisé : Gatekeeper bloque le premier lancement de la copie téléchargée."
