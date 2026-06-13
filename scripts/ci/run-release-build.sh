#!/usr/bin/env bash
set -euo pipefail

artifact_dir="dist/release"
mkdir -p "${artifact_dir}"

# Add repo-specific build steps above this line to populate ${artifact_dir}
# with downloadable release assets before checksums are generated.

mapfile -t artifacts < <(find "${artifact_dir}" -maxdepth 1 -type f ! -name SHA256SUMS | sort)
if [[ ${#artifacts[@]} -eq 0 ]]; then
  echo "No release artifacts were produced in ${artifact_dir}."
  echo "This repo ships no downloadable assets; add build steps to scripts/ci/run-release-build.sh when it does."
  exit 0
fi
(
  cd "${artifact_dir}"
  : > SHA256SUMS
  for entry in "${artifacts[@]}"; do
    sha256sum -- "${entry#"${artifact_dir}/"}" >> SHA256SUMS
  done
)
echo "Wrote ${artifact_dir}/SHA256SUMS for ${#artifacts[@]} artifact(s)."
