#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/sync-project.py
mkdir -p .build/milestones
milestoneName="${1:-current}"
buildConfiguration="${2:-Debug}"
if DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FamilyMove.xcodeproj -scheme FamilyMove -destination 'generic/platform=iOS' -configuration "$buildConfiguration" -derivedDataPath .build/iPadDerivedData CODE_SIGNING_ALLOWED=NO build > ".build/milestones/$milestoneName.log" 2>&1; then
  echo "$milestoneName: BUILD SUCCEEDED"
else
  rg -n -A 5 'error:|BUILD FAILED|fatal error:' ".build/milestones/$milestoneName.log" || tail -40 ".build/milestones/$milestoneName.log"
  exit 1
fi
