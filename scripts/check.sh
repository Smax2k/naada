#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEAM_ID="BG55CF653X"

./scripts/test.sh
./scripts/build.sh release

echo "→ Contrôles de l'artefact"
test -x Naada.app/Contents/MacOS/Naada
plutil -lint Naada.app/Contents/Info.plist >/dev/null
codesign --verify --strict Naada.app

echo "→ Contrôles de la signature Developer ID"
SIGNATURE_INFO="$(codesign -dv --verbose=4 Naada.app 2>&1)"
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

REQUIREMENT="$(codesign -d -r- Naada.app 2>&1)"
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
echo "✓ Signature Developer ID stable (équipe $TEAM_ID, runtime, horodatage ; pas de ticket notarié requis)"

echo "→ Contrôles de l'icône"
for icon_key in CFBundleIconFile CFBundleIconName; do
    icon_value="$(plutil -extract "$icon_key" raw -o - Naada.app/Contents/Info.plist)"
    if [[ "$icon_value" != "AppIcon" ]]; then
        echo "Échec : $icon_key doit valoir AppIcon (valeur : ${icon_value:-absente})." >&2
        exit 1
    fi
done

for icon_output in Assets.car AppIcon.icns; do
    if [[ ! -f "Naada.app/Contents/Resources/$icon_output" ]]; then
        echo "Échec : $icon_output absent du bundle." >&2
        exit 1
    fi
done

ICONSET_DIR="$(mktemp -d -t naada-iconset)"
ASSET_JSON="$(mktemp -t naada-assets)"
trap 'rm -f "$ASSET_JSON"; rm -rf "$ICONSET_DIR"' EXIT
iconutil --convert iconset --output "$ICONSET_DIR/AppIcon.iconset" Naada.app/Contents/Resources/AppIcon.icns
if [[ ! -f "$ICONSET_DIR/AppIcon.iconset/icon_512x512@2x.png" ]]; then
    echo "Échec : l'icône de repli .icns n'embarque pas la taille 1024." >&2
    exit 1
fi

xcrun assetutil --info Naada.app/Contents/Resources/Assets.car > "$ASSET_JSON"
python3 - "$ASSET_JSON" <<'PY'
import json
import sys


def fail(message):
    print(f"Échec : {message}", file=sys.stderr)
    raise SystemExit(1)


with open(sys.argv[1], encoding="utf-8") as handle:
    assets = json.load(handle)


def layers_for(appearance):
    for asset in assets:
        if (
            asset.get("AssetType") == "IconGroup"
            and asset.get("Name") == "AppIcon/Resonance"
            and asset.get("Appearance") == appearance
        ):
            return {
                layer.get("Name", "").rsplit("/", 1)[-1]: layer.get("LayerOpacity")
                for layer in asset.get("Layers", [])
            }
    fail(f"apparence {appearance} absente d'Assets.car")


expected = {
    "NSAppearanceNameAqua": {"naada-light-full": 1, "naada-dark-full": 0},
    "NSAppearanceNameDarkAqua": {"naada-light-full": 0, "naada-dark-full": 1},
}
stacks = {
    asset.get("Appearance")
    for asset in assets
    if asset.get("AssetType") == "IconImageStack"
}
for appearance in expected:
    if appearance not in stacks:
        fail(f"pile d'images {appearance} absente d'Assets.car")

for appearance, wanted in expected.items():
    layers = layers_for(appearance)
    for name, opacity in wanted.items():
        if layers.get(name) != opacity:
            fail(
                f"{appearance} : la couche {name} doit avoir l'opacité {opacity}, "
                f"valeur trouvée {layers.get(name)!r}"
            )

images = {
    asset.get("Name"): asset
    for asset in assets
    if asset.get("AssetType") == "Image"
    and asset.get("Name")
    in {
        "AppIcon_Assets/naada-light-full",
        "AppIcon_Assets/naada-dark-full",
    }
}
if len(images) != 2:
    fail("les deux images sources de l'icône sont absentes d'Assets.car")
for name, asset in images.items():
    if asset.get("PixelWidth") != 1024 or asset.get("PixelHeight") != 1024:
        fail(
            f"{name} compilée en {asset.get('PixelWidth')}x{asset.get('PixelHeight')}, "
            "attendu 1024x1024"
        )
digests = {asset.get("SHA1Digest") for asset in images.values()}
if None in digests or len(digests) != 2:
    fail("les images claire et sombre compilées sont absentes ou identiques")

print("✓ Variantes clair/sombre compilées et distinctes dans Assets.car")
PY

if otool -L Naada.app/Contents/MacOS/Naada | grep -qi 'shine'; then
    echo "Échec : Shine doit être lié statiquement, pas via un dylib externe." >&2
    exit 1
fi

if otool -L Naada.app/Contents/MacOS/Naada | grep -qiE '/(opt/homebrew|usr/local)'; then
    echo "Échec : dépendance hors système détectée." >&2
    exit 1
fi

echo "✓ Tests, bundle, signature et liaisons système vérifiés"
