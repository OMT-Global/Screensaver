#!/usr/bin/env bash
set -euo pipefail

tag="${GITHUB_REF_NAME:-}"
if [[ -z "${tag}" ]]; then
  echo "GITHUB_REF_NAME is required to validate release versions." >&2
  exit 1
fi
prefix="v"
version="${tag#"${prefix}"}"

echo "No release version surfaces are configured in project.bootstrap.yaml."
echo "Skipping version validation for ${tag}; version bump pull requests must merge before the release tag is pushed."
