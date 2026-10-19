#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/sync-project.py
mkdir -p .build/milestones
macConfiguration="${1:-Debug}"
macBuildLog=".build/milestones/mac-${macConfiguration}.log"
if DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project FamilyMove.xcodeproj -scheme FamilyMove \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -configuration "$macConfiguration" -derivedDataPath .build/Mac \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build > "$macBuildLog" 2>&1; then
    echo "MacBook ${macConfiguration}: BUILD SUCCEEDED"
    echo "$PWD/.build/Mac/Build/Products/${macConfiguration}-maccatalyst/FamilyMove.app"
else
    rg -n -A 5 'error:|BUILD FAILED|fatal error:' "$macBuildLog" || tail -40 "$macBuildLog"
    exit 1
fi
