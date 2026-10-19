#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/build-mac.sh Debug
open .build/Mac/Build/Products/Debug-maccatalyst/FamilyMove.app
