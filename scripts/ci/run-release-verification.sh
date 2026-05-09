#!/usr/bin/env bash
set -euo pipefail

bash scripts/ci/run-fast-checks.sh
bash scripts/ci/run-extended-validation.sh
