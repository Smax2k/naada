#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/test.sh
./scripts/build.sh release

echo "→ Contrôles de l'artefact"
test -x Naada.app/Contents/MacOS/Naada
plutil -lint Naada.app/Contents/Info.plist >/dev/null
codesign --verify --strict Naada.app

if otool -L Naada.app/Contents/MacOS/Naada | grep -qi 'shine'; then
    echo "Échec : Shine doit être lié statiquement, pas via un dylib externe." >&2
    exit 1
fi

if otool -L Naada.app/Contents/MacOS/Naada | grep -qiE '/(opt/homebrew|usr/local)'; then
    echo "Échec : dépendance hors système détectée." >&2
    exit 1
fi

echo "✓ Tests, bundle, signature et liaisons système vérifiés"
