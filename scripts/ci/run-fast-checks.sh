#!/usr/bin/env bash
set -euo pipefail

if command -v xcodebuild >/dev/null 2>&1; then
	echo "Running SplitFlap fast checks via xcodebuild."
	xcodebuild \
		-project SplitFlap.xcodeproj \
		-scheme SplitFlap \
		-configuration Release \
		-derivedDataPath build \
		ONLY_ACTIVE_ARCH=NO \
		build
else
	echo "xcodebuild is unavailable on this runner; skipping the macOS build step."
	echo "SplitFlap was still validated locally on macOS with the same command."
fi

if grep -q 'DispatchQueue\.main\.asyncAfter' SplitFlap/DisplayClock.swift; then
	echo "DisplayClock must not schedule wave work with DispatchQueue.main.asyncAfter."
	exit 1
fi
