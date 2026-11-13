#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEAM_ID="BG55CF653X"

./scripts/test.sh
./scripts/build.sh release

echo "→ Contrôles du chemin audio seul"
FORBIDDEN_SCREEN_PATTERN='import ScreenCaptureKit|SCStream|SCShareableContent|SCContentFilter|NSScreenCaptureUsageDescription'
if grep -REn "$FORBIDDEN_SCREEN_PATTERN" Sources packaging >/dev/null; then
    echo "Échec : un symbole ou une clé d'enregistrement d'écran subsiste :" >&2
    grep -REn "$FORBIDDEN_SCREEN_PATTERN" Sources packaging >&2
    exit 1
fi

FORBIDDEN_TAP_PATTERN='CATapMuted|kAudioHardwarePropertyDefaultOutputDevice|muteBehavior *= *\.(muted|mutedWhenTapped)|isPrivate *= *false|isExclusive *= *true|usesBundleIdentifiers *= *true|targetsDefaultOutputDevice *= *true|stereoGlobalTap|monoGlobalTap|GlobalTapButExclude'
if grep -REn "$FORBIDDEN_TAP_PATTERN" Sources >/dev/null; then
    echo "Échec : un tap muet ou un changement de sortie par défaut subsiste :" >&2
    grep -REn "$FORBIDDEN_TAP_PATTERN" Sources >&2
    exit 1
fi

# Les clés numériques de l'agrégat sont des CFNumber entiers : un Bool Swift
# se bride en CFBoolean, que CFNumberGetValue refuse.
FORBIDDEN_AGGREGATE_PATTERN='IsPrivateKey: *true|IsStackedKey: *false|TapAutoStartKey: *true|NSNumber\(value: *(true|false)\)'
if grep -REn "$FORBIDDEN_AGGREGATE_PATTERN" Sources >/dev/null; then
    echo "Échec : un réglage d'agrégat est encore un booléen au lieu d'un CFNumber :" >&2
    grep -REn "$FORBIDDEN_AGGREGATE_PATTERN" Sources >&2
    exit 1
fi

if grep -REn 'tapAutoStart: *true|isPrivate: *false|isStacked: *true' Sources/Naada >/dev/null; then
    echo "Échec : le moteur ne doit jamais activer tapautostart, ni rendre l'agrégat public, ni l'empiler." >&2
    exit 1
fi

for required_symbol in \
    kAudioHardwarePropertyTranslatePIDToProcessObject \
    AudioHardwareCreateProcessTap \
    AudioHardwareCreateAggregateDevice \
    kAudioTapPropertyFormat \
    kAudioDevicePropertyStreams \
    kAudioStreamPropertyVirtualFormat \
    TapAggregateComposition \
    AudioBufferLayout.analyze; do
    if ! grep -Fq "$required_symbol" Sources/Naada/AudioCaptureEngine.swift; then
        echo "Échec : le chemin de tap de processus n'utilise pas $required_symbol." >&2
        exit 1
    fi
done

# Les clés littérales du plan pur sont confrontées aux constantes du SDK
# dans les tests, qui tournent avant ce contrôle.
for required_symbol in \
    kAudioAggregateDeviceTapListKey \
    kAudioSubTapUIDKey \
    kAudioAggregateDeviceIsPrivateKey \
    kAudioAggregateDeviceIsStackedKey \
    kAudioAggregateDeviceTapAutoStartKey \
    kAudioSubTapDriftCompensationKey; do
    if ! grep -Fq "$required_symbol" Tests/NaadaCoreTests/TapAggregateCompositionTests.swift; then
        echo "Échec : $required_symbol n'est pas vérifié face au plan d'agrégat." >&2
        exit 1
    fi
done

for required_symbol in waitingForAudio markFirstBufferReceived; do
    if ! grep -Fq "$required_symbol" Sources/NaadaCore/CaptureLifecycleState.swift; then
        echo "Échec : l'automate de capture n'expose pas $required_symbol." >&2
        exit 1
    fi
done

if ! grep -Fq 'muteBehavior = .unmuted' Sources/Naada/AudioCaptureEngine.swift; then
    echo "Échec : le tap doit rester explicitement non muet." >&2
    exit 1
fi

AUDIO_USAGE="$(plutil -extract NSAudioCaptureUsageDescription raw -o - Naada.app/Contents/Info.plist)"
if [[ -z "$AUDIO_USAGE" ]]; then
    echo "Échec : NSAudioCaptureUsageDescription est absente ou vide." >&2
    exit 1
fi
if [[ "$AUDIO_USAGE" != *"no images"* || "$AUDIO_USAGE" != *"stays audible"* || "$AUDIO_USAGE" != *"before your click"* ]]; then
    echo "Échec : la description audio anglaise doit préciser no images, stays audible et before your click." >&2
    exit 1
fi

MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw -o - Naada.app/Contents/Info.plist)"
if [[ "$MIN_MACOS" != "14.2" ]]; then
    echo "Échec : LSMinimumSystemVersion doit valoir 14.2 (valeur : ${MIN_MACOS:-absente})." >&2
    exit 1
fi

if plutil -extract NSScreenCaptureUsageDescription raw -o - Naada.app/Contents/Info.plist >/dev/null 2>&1; then
    echo "Échec : NSScreenCaptureUsageDescription est encore déclarée." >&2
    exit 1
fi
echo "✓ Aucun chemin d'enregistrement d'écran, tap privé non muet, autorisation audio et minimum 14.2"

echo "→ Contrôles de la localisation en/fr"
DEVELOPMENT_REGION="$(plutil -extract CFBundleDevelopmentRegion raw -o - Naada.app/Contents/Info.plist)"
if [[ "$DEVELOPMENT_REGION" != "en" ]]; then
    echo "Échec : CFBundleDevelopmentRegion doit valoir en (valeur : ${DEVELOPMENT_REGION:-absente})." >&2
    exit 1
fi

for language in en fr; do
    LANGUAGE_DIR="Naada.app/Contents/Resources/$language.lproj"
    for table in Localizable.strings InfoPlist.strings; do
        if [[ ! -f "$LANGUAGE_DIR/$table" ]]; then
            echo "Échec : $language.lproj/$table absent du bundle." >&2
            exit 1
        fi
    done
done

python3 - <<'PY'
import json
import subprocess
import sys


def fail(message):
    print(f"Échec : {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path):
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", path],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"{path} illisible : {result.stderr.strip()}")
    return json.loads(result.stdout)


base_plist = load("Naada.app/Contents/Info.plist")
if base_plist.get("CFBundleDevelopmentRegion") != "en":
    fail("la région de développement du bundle n'est pas en")

for table in ("Localizable.strings", "InfoPlist.strings"):
    en = load(f"Naada.app/Contents/Resources/en.lproj/{table}")
    fr = load(f"Naada.app/Contents/Resources/fr.lproj/{table}")
    missing = sorted(set(en) - set(fr))
    extra = sorted(set(fr) - set(en))
    if missing:
        fail(f"{table} : clés absentes du français : {missing}")
    if extra:
        fail(f"{table} : clés absentes de l'anglais : {extra}")
    empty = sorted(key for key, value in {**en, **fr}.items() if not value)
    if empty:
        fail(f"{table} : traductions vides : {empty}")
    if not en:
        fail(f"{table} : table vide")

en_plist = load("Naada.app/Contents/Resources/en.lproj/InfoPlist.strings")
fr_plist = load("Naada.app/Contents/Resources/fr.lproj/InfoPlist.strings")
if en_plist.get("NSAudioCaptureUsageDescription") != base_plist.get("NSAudioCaptureUsageDescription"):
    fail("la description audio anglaise diffère du Info.plist de base")
if en_plist.get("NSHumanReadableCopyright") != base_plist.get("NSHumanReadableCopyright"):
    fail("le copyright anglais diffère du Info.plist de base")
french_usage = fr_plist.get("NSAudioCaptureUsageDescription", "")
for phrase in ("aucune image", "reste audible", "avant votre clic"):
    if phrase not in french_usage:
        fail(f"la description audio française ne contient pas « {phrase} »")

print("✓ Localisations en/fr présentes, région en, clés et description audio paritaires")
PY

python3 - <<'PY'
import pathlib
import re
import sys

FRENCH_WORDS = re.compile(
    r"\b(Aucun|Aucune|Choisir|Dossier|Enregistrer|Enregistrement|Arrêter|"
    r"Supprimer|Annuler|Prêt|Préparation|Finalisation|Réunion|Renommer|"
    r"Appliquer|Créer|Fermer|Masquer|Afficher|Impossible|Autorisation)\b"
)
FRENCH_ACCENTS = re.compile(r"[éèêàçùôîûœÉÈÊÀÇÙÔÎÛŒ]")

problems = []
for path in sorted(pathlib.Path("Sources").rglob("*.swift")):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    for match in re.finditer(r'"((?:[^"\\]|\\.)*)"', text):
        literal = match.group(1)
        if FRENCH_ACCENTS.search(literal) or FRENCH_WORDS.search(literal):
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"{path}:{line} : {literal}")

if problems:
    print(
        "Échec : des textes visibles français subsistent hors localisation :\n"
        + "\n".join(problems),
        file=sys.stderr,
    )
    raise SystemExit(1)
print("✓ Aucun texte visible français hors des fichiers de localisation")
PY

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

if otool -L Naada.app/Contents/MacOS/Naada | grep -q 'ScreenCaptureKit.framework'; then
    echo "Échec : le binaire lie encore ScreenCaptureKit." >&2
    exit 1
fi

if ! otool -L Naada.app/Contents/MacOS/Naada | grep -q 'CoreAudio.framework'; then
    echo "Échec : le binaire ne lie pas CoreAudio." >&2
    exit 1
fi

echo "✓ Tests, bundle, signature, chemin audio seul et liaisons système vérifiés"
