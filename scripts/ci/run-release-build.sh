#!/usr/bin/env bash
set -euo pipefail

artifact_dir="dist/release"
product_name="Flapline"
saver_path="build/Build/Products/Release/${product_name}.saver"
staging_dir="dist/staging"
artifact_list="$(mktemp "${TMPDIR:-/tmp}/flapline-artifacts.XXXXXX")"

cleanup() {
  rm -f "${artifact_list}"
}
trap cleanup EXIT

mkdir -p "${artifact_dir}"
rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"

xcodebuild \
  -project SplitFlap.xcodeproj \
  -scheme SplitFlap \
  -configuration Release \
  -derivedDataPath build \
  ONLY_ACTIVE_ARCH=NO \
  build

if [[ ! -d "${saver_path}" ]]; then
  echo "Expected release build output was not found: ${saver_path}" >&2
  exit 1
fi

cp -R "${saver_path}" "${staging_dir}/${product_name}.saver"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${staging_dir}/${product_name}.saver"
else
  echo "DEVELOPER_ID_APPLICATION is not set; producing an unsigned development artifact."
  echo "Public releases should be Developer ID signed and notarized before publication."
fi

(
  cd "${staging_dir}"
  /usr/bin/ditto -c -k --keepParent "${product_name}.saver" "../release/${product_name}.saver.zip"
)

find "${artifact_dir}" -maxdepth 1 -type f ! -name SHA256SUMS -exec basename {} \; | sort > "${artifact_list}"
artifact_count="$(wc -l < "${artifact_list}" | tr -d ' ')"
if [[ "${artifact_count}" -eq 0 ]]; then
  echo "No release artifacts were produced in ${artifact_dir}."
  echo "This repo ships no downloadable assets; add build steps to scripts/ci/run-release-build.sh when it does."
  exit 0
fi
(
  cd "${artifact_dir}"
  : > SHA256SUMS
  while IFS= read -r entry; do
    shasum -a 256 -- "${entry}" >> SHA256SUMS
  done < "${artifact_list}"
)
echo "Wrote ${artifact_dir}/SHA256SUMS for ${artifact_count} artifact(s)."
