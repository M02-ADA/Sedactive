#!/bin/bash
set -euo pipefail
taskRoot="$(cd "$(dirname "$0")/.." && pwd)"
taskBuildPath="$taskRoot/.build/CoreChecks"
mkdir -p "$taskBuildPath/module-cache"
swiftc -D CORE_TEST_RUNNER -module-cache-path "$taskBuildPath/module-cache" \
    "$taskRoot/FamilyMove/Games/Shared/GameConstants.swift" \
    "$taskRoot/FamilyMove/BodyTracking/PlayerTracker.swift" \
    "$taskRoot/FamilyMove/BodyTracking/TrackedPlayer.swift" \
    "$taskRoot/FamilyMove/BodyTracking/PositionSmoother.swift" \
    "$taskRoot/FamilyMove/BodyTracking/BodyObservation.swift" \
    "$taskRoot/FamilyMove/BodyTracking/CoordinateMapper.swift" \
    "$taskRoot/Tests/TrackingCoreTests/TrackingCoreTests.swift" \
    "$taskRoot/Tests/CommandLineRunner.swift" \
    -o "$taskBuildPath/TrackingCoreChecks"
"$taskBuildPath/TrackingCoreChecks"
