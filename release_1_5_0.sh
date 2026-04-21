#!/usr/bin/env bash
set -euo pipefail

# Coordinated multi-repo release helper for the flux ecosystem.
# Default mode is dry-run (safe). Use --execute to perform git writes/pushes.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.5.0"
TAG="v${VERSION}"
OWNER="jarrod-dalton"
EXECUTE=0
CREATE_GH_RELEASE=0

REPOS=(
  "subrepos/fluxCore"
  "subrepos/fluxPrepare"
  "subrepos/fluxForecast"
  "subrepos/fluxValidation"
  "subrepos/fluxOrchestrate"
  "subrepos/fluxModelTemplate"
  "subrepos/fluxASCVD"
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --execute            Perform commit/tag/push actions (default is dry-run)
  --gh-release         Create GitHub releases using gh CLI
  --version X.Y.Z      Override version (default: ${VERSION})
  --owner USER         GitHub owner/org for gh release (default: ${OWNER})
  -h, --help           Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --execute
  $(basename "$0") --execute --gh-release --owner my-org
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) EXECUTE=1; shift ;;
    --gh-release) CREATE_GH_RELEASE=1; shift ;;
    --version) VERSION="$2"; TAG="v${VERSION}"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

COMMIT_MSG="Release ${TAG}: coordinated ecosystem update"

echo "Root: ${ROOT_DIR}"
echo "Version: ${VERSION}"
echo "Tag: ${TAG}"
echo "Mode: $([[ ${EXECUTE} -eq 1 ]] && echo EXECUTE || echo DRY-RUN)"
echo

run_cmd() {
  if [[ ${EXECUTE} -eq 1 ]]; then
    "$@"
  else
    echo "[DRY-RUN] $*"
  fi
}

for repo in "${REPOS[@]}"; do
  dir="${ROOT_DIR}/${repo}"
  repo_label="$(basename "${repo}")"
  if [[ ! -d "${dir}/.git" ]]; then
    echo "Skipping ${repo_label}: not a git repo"
    continue
  fi

  echo "=== ${repo_label} ==="
  git -C "${dir}" status --short

  run_cmd git -C "${dir}" add -A
  run_cmd git -C "${dir}" commit -m "${COMMIT_MSG}"
  run_cmd git -C "${dir}" tag -a "${TAG}" -m "${TAG}"
  run_cmd git -C "${dir}" push origin HEAD
  run_cmd git -C "${dir}" push origin "${TAG}"

  if [[ ${CREATE_GH_RELEASE} -eq 1 ]]; then
    remote_url="$(git -C "${dir}" remote get-url origin)"
    # Handles: https://github.com/user/repo.git
    repo_name="$(basename -s .git "${remote_url}")"
    news_file="${dir}/NEWS.md"

    if [[ -f "${news_file}" ]]; then
      if [[ ${EXECUTE} -eq 1 ]]; then
        gh release create "${TAG}" \
          --repo "${OWNER}/${repo_name}" \
          --title "${TAG}" \
          --notes-file "${news_file}"
      else
        echo "[DRY-RUN] gh release create ${TAG} --repo ${OWNER}/${repo_name} --title ${TAG} --notes-file ${news_file}"
      fi
    else
      echo "No NEWS.md in ${repo_label}; skipping gh release note file"
    fi
  fi

  echo

done

echo "Done."
