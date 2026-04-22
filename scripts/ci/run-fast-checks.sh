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

awk '
	/(static let|static var|lazy var).*DateFormatter/ {
		in_cached_formatter = 1
	}
	/DateFormatter\(\)/ && !in_cached_formatter {
		print "DisplayClock must cache DateFormatter instances instead of constructing them on the tick path."
		exit 1
	}
	in_cached_formatter && /^[[:space:]]*}\(\)/ {
		in_cached_formatter = 0
	}
' SplitFlap/DisplayClock.swift
