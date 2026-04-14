#!/usr/bin/env bash
set -euo pipefail

echo "Running SplitFlap fast checks via xcodebuild."
xcodebuild \
	-project SplitFlap.xcodeproj \
	-scheme SplitFlap \
	-configuration Release \
	-derivedDataPath build \
	ONLY_ACTIVE_ARCH=NO \
	build
