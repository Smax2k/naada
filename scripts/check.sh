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
# Seule la sonde peut lire la sortie par défaut, pour comparer avant/après ;
# elle ne l'écrit jamais (contrôle AudioObjectSetPropertyData ci-dessous).
TAP_VIOLATIONS="$(grep -REn "$FORBIDDEN_TAP_PATTERN" Sources \
    | grep -Ev '^Sources/Naada/CaptureProbe.swift:[0-9]+:[[:space:]]*mSelector: kAudioHardwarePropertyDefaultOutputDevice,$' || true)"
if [[ -n "$TAP_VIOLATIONS" ]]; then
    echo "Échec : un tap muet ou un changement de sortie par défaut subsiste :" >&2
    printf '%s\n' "$TAP_VIOLATIONS" >&2
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

echo "→ Contrôles de la permission microphone"
# La permission micro n'est demandée qu'au démarrage explicite, par le moteur.
if ! grep -Fq 'AVCaptureDevice.requestAccess(for: .audio)' Sources/Naada/AudioCaptureEngine.swift; then
    echo "Échec : le moteur ne demande pas la permission microphone au démarrage." >&2
    exit 1
fi

REQUEST_ACCESS_VIOLATIONS="$(grep -REn 'requestAccess' Sources \
    | grep -Ev '^Sources/Naada/AudioCaptureEngine.swift:[0-9]+:' || true)"
if [[ -n "$REQUEST_ACCESS_VIOLATIONS" ]]; then
    echo "Échec : requestAccess doit rester confiné à AudioCaptureEngine.swift :" >&2
    printf '%s\n' "$REQUEST_ACCESS_VIOLATIONS" >&2
    exit 1
fi

# Le catalogue énumère les entrées sans en ouvrir une ni demander la permission.
# Les commentaires sont retirés : une note « AVCaptureDevice n'est pas utilisé »
# ne doit pas faire échouer le contrôle.
MICROPHONE_CATALOG="Sources/Naada/MicrophoneCatalog.swift"
if [[ -f "$MICROPHONE_CATALOG" ]]; then
python3 - "$MICROPHONE_CATALOG" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"//[^\n]*", "", text)
for pattern in ("AVCaptureDevice", "requestAccess"):
    if pattern in text:
        print(
            f"Échec : {path} utilise {pattern} ; le catalogue ne doit ni ouvrir "
            "un périphérique ni demander la permission.",
            file=sys.stderr,
        )
        raise SystemExit(1)
PY
fi
echo "✓ Permission micro demandée seulement par le moteur, catalogue sans accès direct"

# Le plan des descendants audio reste pur et vérifiable sans Core Audio.
for required_symbol in \
    audio.mojom.AudioService \
    --service-sandbox-type=audio \
    chrome_crashpad_handler \
    video_capture.mojom.VideoCaptureService \
    network.mojom.NetworkService \
    isDescendant \
    VerifiedAudioHelperProcess \
    TranslatedAudioHelper \
    ApplicationAudioTapSelection; do
    if ! grep -Fq -- "$required_symbol" Sources/NaadaCore/ApplicationAudioProcesses.swift; then
        echo "Échec : le plan des descendants audio n'expose pas $required_symbol." >&2
        exit 1
    fi
done

for required_symbol in \
    ApplicationAudioProcesses.plan \
    ApplicationAudioTapSelection \
    translatedObjectIDs \
    LiveProcessTable.snapshot \
    didRetryForAudioHelper \
    refreshAudioHelpersIfNeeded; do
    if ! grep -Fq "$required_symbol" Sources/Naada/AudioCaptureEngine.swift; then
        echo "Échec : le moteur n'utilise pas $required_symbol." >&2
        exit 1
    fi
done

for required_symbol in \
    verifiedApplicationAudio \
    audioHelperWithoutProof \
    multipleApplications; do
    if ! grep -Fq "$required_symbol" Sources/NaadaCore/ProcessTapConstraints.swift; then
        echo "Échec : les contraintes n'exposent pas $required_symbol." >&2
        exit 1
    fi
done

if grep -REn 'does not capture|ne capture pas|which Naada does not capture' \
    Sources packaging >/dev/null; then
    echo "Échec : un message prétend encore que les helpers audio ne sont pas capturés :" >&2
    grep -REn 'does not capture|ne capture pas|which Naada does not capture' \
        Sources packaging >&2
    exit 1
fi

for required_key in \
    "The selected process is not playing sound. Start playback" \
    "Naada also captures the application's audio helper processes."; do
    for table in packaging/en.lproj/Localizable.strings packaging/fr.lproj/Localizable.strings; do
        if ! grep -Fq -- "$required_key" "$table"; then
            echo "Échec : $table ne contient pas le message corrigé : $required_key" >&2
            exit 1
        fi
    done
done

# La sonde doit sortir avant toute fenêtre, toute scène et toute activation.
NAADA_APP="Sources/Naada/NaadaApp.swift"
if ! grep -Fq 'CaptureProbe.exitIfRequested' "$NAADA_APP"; then
    echo "Échec : la sonde de capture n'est pas branchée dans NaadaApp." >&2
    exit 1
fi
PROBE_LINE="$(grep -n 'CaptureProbe.exitIfRequested' "$NAADA_APP" | head -1 | cut -d: -f1)"
WINDOW_LINE="$(grep -n 'WindowGroup' "$NAADA_APP" | head -1 | cut -d: -f1)"
ACTIVATE_LINE="$(grep -n 'NSApp.activate' "$NAADA_APP" | head -1 | cut -d: -f1)"
if [[ -z "$PROBE_LINE" || -z "$WINDOW_LINE" || "$PROBE_LINE" -ge "$WINDOW_LINE" ]]; then
    echo "Échec : la sonde doit être appelée avant la première scène." >&2
    exit 1
fi
if [[ -n "$ACTIVATE_LINE" && "$PROBE_LINE" -ge "$ACTIVATE_LINE" ]]; then
    echo "Échec : la sonde doit être appelée avant l'activation de l'application." >&2
    exit 1
fi

if ! grep -Fq 'ApplicationAudioProcesses.plan' \
    Tests/NaadaCoreTests/ApplicationAudioProcessesTests.swift; then
    echo "Échec : les tests ne couvrent pas le plan des descendants audio." >&2
    exit 1
fi

for required_symbol in \
    ApplicationAudioTapSelection \
    requestedRootPID \
    rootIsTranslated \
    tappedPIDs \
    untranslatedPIDs \
    failCapture; do
    if ! grep -Fq "$required_symbol" Sources/Naada/AudioCaptureEngine.swift; then
        echo "Échec : le moteur ne distingue pas ou ne gère pas $required_symbol." >&2
        exit 1
    fi
done

for required_symbol in \
    callbackRMSMax \
    mp3RMS \
    defaultOutputUnchanged \
    defaultOutputIdentity \
    proofFileName \
    isOutsideRecordingsFolder \
    writeProof \
    SessionSettingsStore.outputFolderPathKey; do
    if ! grep -Fq "$required_symbol" Sources/Naada/CaptureProbe.swift; then
        echo "Échec : la sonde n'exige pas ou n'enregistre pas $required_symbol." >&2
        exit 1
    fi
done

if grep -Fq 'AudioObjectSetPropertyData' Sources/Naada/CaptureProbe.swift; then
    echo "Échec : la sonde doit seulement lire la sortie par défaut, jamais la modifier." >&2
    exit 1
fi

python3 - <<'PY'
import pathlib
import sys

text = pathlib.Path("Sources/Naada/AudioCaptureEngine.swift").read_text()
start = text.index("private func refreshAudioHelpersIfNeeded")
end = text.index("// MARK: - IOProc", start)
block = text[start:end]

try:
    invalidate = block.index("activeGeneration.withLock { $0 = 0 }")
    destroy = block.index("Self.destroy(endpoints)")
    create = block.index("createResources(")
except ValueError:
    print("Échec : la reprise ne détruit pas clairement l'ancien tap avant le nouveau.", file=sys.stderr)
    raise SystemExit(1)

if not invalidate < destroy < create:
    print(
        "Échec : la reprise doit invalider la génération, détruire l'ancien tap, puis créer le nouveau.",
        file=sys.stderr,
    )
    raise SystemExit(1)

print("✓ Reprise sans chevauchement : génération invalidée, ancien tap détruit avant création")
PY

echo "✓ Diagnostic racine/tapés, double RMS, sortie par défaut lue seulement, preuve hors dossier humain"

AUDIO_USAGE="$(plutil -extract NSAudioCaptureUsageDescription raw -o - Naada.app/Contents/Info.plist)"
if [[ -z "$AUDIO_USAGE" ]]; then
    echo "Échec : NSAudioCaptureUsageDescription est absente ou vide." >&2
    exit 1
fi
if [[ "$AUDIO_USAGE" != *"no images"* || "$AUDIO_USAGE" != *"stays audible"* || "$AUDIO_USAGE" != *"before your click"* ]]; then
    echo "Échec : la description audio anglaise doit préciser no images, stays audible et before your click." >&2
    exit 1
fi

MICROPHONE_USAGE="$(plutil -extract NSMicrophoneUsageDescription raw -o - Naada.app/Contents/Info.plist)"
if [[ -z "$MICROPHONE_USAGE" ]]; then
    echo "Échec : NSMicrophoneUsageDescription est absente ou vide." >&2
    exit 1
fi
if [[ "$MICROPHONE_USAGE" != *"only when you choose"* || "$MICROPHONE_USAGE" != *"after your click"* || "$MICROPHONE_USAGE" != *"no images"* || "$MICROPHONE_USAGE" != *"stays audible"* ]]; then
    echo "Échec : la description micro anglaise doit préciser only when you choose, after your click, no images et stays audible." >&2
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

if en_plist.get("NSMicrophoneUsageDescription") != base_plist.get("NSMicrophoneUsageDescription"):
    fail("la description microphone anglaise diffère du Info.plist de base")
french_microphone_usage = fr_plist.get("NSMicrophoneUsageDescription", "")
for phrase in ("aucune image", "reste audible", "si vous en choisissez", "après votre clic"):
    if phrase not in french_microphone_usage:
        fail(f"la description microphone française ne contient pas « {phrase} »")

print("✓ Localisations en/fr présentes, région en, clés et descriptions audio/micro paritaires")
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
