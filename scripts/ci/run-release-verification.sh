#!/usr/bin/env bash
set -euo pipefail
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required for SplitFlap release verification." >&2
  exit 1
fi

xcodebuild \
  -project SplitFlap.xcodeproj \
  -scheme SplitFlap \
  -configuration Release \
  -derivedDataPath build \
  ONLY_ACTIVE_ARCH=NO \
  build

bash scripts/ci/run-fast-checks.sh
