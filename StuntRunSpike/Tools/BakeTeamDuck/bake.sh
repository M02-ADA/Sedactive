#!/bin/sh
# Re-bakes the TEAM DUCK shatter sprite sheet into the app's resources (macOS only; not shipped).
set -e
cd "$(dirname "$0")/../.."
OUT="${TMPDIR:-/tmp}/bake-teamduck"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun swiftc -O -swift-version 6 Tools/BakeTeamDuck/main.swift -o "$OUT"
"$OUT" StuntRunSpike
