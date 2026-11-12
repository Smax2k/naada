#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Tests purs (aucune capture, aucun périphérique audio)"
swift test "$@"
