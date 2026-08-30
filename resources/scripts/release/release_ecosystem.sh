#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point. Keep release logic in one canonical script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

exec "${ROOT_DIR}/scripts/release/release_ecosystem.sh" "$@"
