#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="${1:-jarrod-dalton}"

cd "${ROOT_DIR}"

git submodule set-url fluxCore "https://github.com/${OWNER}/fluxCore.git"
git submodule set-url fluxPrepare "https://github.com/${OWNER}/fluxPrepare.git"
git submodule set-url fluxForecast "https://github.com/${OWNER}/fluxForecast.git"
git submodule set-url fluxValidation "https://github.com/${OWNER}/fluxValidation.git"
git submodule set-url fluxOrchestrate "https://github.com/${OWNER}/fluxOrchestrate.git"
git submodule set-url fluxASCVD "https://github.com/${OWNER}/fluxASCVD.git"
git submodule set-url fluxModelTemplate "https://github.com/${OWNER}/fluxModelTemplate.git"

git submodule sync --recursive

git -C fluxCore remote set-url origin "https://github.com/${OWNER}/fluxCore.git"
git -C fluxPrepare remote set-url origin "https://github.com/${OWNER}/fluxPrepare.git"
git -C fluxForecast remote set-url origin "https://github.com/${OWNER}/fluxForecast.git"
git -C fluxValidation remote set-url origin "https://github.com/${OWNER}/fluxValidation.git"
git -C fluxOrchestrate remote set-url origin "https://github.com/${OWNER}/fluxOrchestrate.git"
git -C fluxASCVD remote set-url origin "https://github.com/${OWNER}/fluxASCVD.git"
git -C fluxModelTemplate remote set-url origin "https://github.com/${OWNER}/fluxModelTemplate.git"

echo "Submodule URLs updated to flux* for owner '${OWNER}'."
