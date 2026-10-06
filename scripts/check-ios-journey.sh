#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_build_dir=$(mktemp -d)
trap 'rm -rf "$task_build_dir"' EXIT
xcrun swiftc ios/BTownBus/Model/TransitModels.swift ios/BTownBus/Model/TripMath.swift ios/BTownBus/Model/RideJourney.swift ios/BTownBus/Model/WalkingProgress.swift ios/BTownBus/Model/WalkingRoutePreference.swift ios/Tests/JourneyChecks.swift -o "$task_build_dir/journey-checks"
"$task_build_dir/journey-checks"
