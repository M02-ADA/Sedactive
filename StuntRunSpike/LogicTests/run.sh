#!/bin/sh
# Compiles the platform-independent gameplay logic with the test driver and runs it on macOS.
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/stuntrun-logic-tests"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun swiftc -swift-version 6 \
  StuntRunSpike/Pose.swift StuntRunSpike/SquatDetector.swift StuntRunSpike/CoopLogic.swift StuntRunSpike/JungleLogic.swift StuntRunSpike/JungleAnimation.swift StuntRunSpike/PiranhaLogic.swift StuntRunSpike/JumpSweepLogic.swift StuntRunSpike/LaserLogic.swift StuntRunSpike/MoonLogic.swift StuntRunSpike/OrientationGuard.swift LogicTests/main.swift -o "$OUT"
"$OUT"
