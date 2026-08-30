#!/usr/bin/env bash
set -euo pipefail

# Coordinated multi-repo release helper for the flux ecosystem.
# Release commits must already exist, be clean, and be synchronized with origin.
# Default mode is a mutation-free preflight; use --execute only after every
# repository passes that preflight.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="2.1.0"
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
  "."
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --execute            Push commits, create tags, and push tags after preflight
  --gh-release         Create GitHub releases using gh CLI
  --version X.Y.Z      Override version (default: ${VERSION})
  --owner USER         GitHub owner/org for gh release (default: ${OWNER})
  -h, --help           Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --execute
  $(basename "$0") --execute --gh-release --owner my-org

Release candidates must already be committed and clean. The root repository is
processed last so its release commit can record the six final submodule commits.
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

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: --version must use X.Y.Z form" >&2
  exit 1
fi

echo "Root: ${ROOT_DIR}"
echo "Version: ${VERSION}"
echo "Tag: ${TAG}"
echo "Mode: $([[ ${EXECUTE} -eq 1 ]] && echo EXECUTE || echo DRY-RUN)"
echo

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ ${CREATE_GH_RELEASE} -eq 1 ]]; then
  command -v gh >/dev/null 2>&1 || fail "gh CLI is required for --gh-release"
  gh auth status --hostname github.com >/dev/null 2>&1 || \
    fail "gh CLI is not authenticated for github.com"
fi

notes_dir=""
cleanup() {
  if [[ -n "${notes_dir}" && -d "${notes_dir}" ]]; then
    rm -rf -- "${notes_dir}"
  fi
}
trap cleanup EXIT

if [[ ${CREATE_GH_RELEASE} -eq 1 ]]; then
  notes_dir="$(mktemp -d "${TMPDIR:-/tmp}/flux-release-notes.XXXXXX")"
fi

extract_news_section() {
  local source_file="$1"
  local output_file="$2"
  awk -v version="${VERSION}" '
    /^## / {
      if (printing) exit
      if (index($0, version) > 0) printing = 1
    }
    printing { print }
  ' "${source_file}" > "${output_file}"
  [[ -s "${output_file}" ]] || fail "could not extract ${VERSION} notes from ${source_file}"
}

# Pass 1 validates every repository before any tag or release is created.
for repo in "${REPOS[@]}"; do
  dir="${ROOT_DIR}/${repo}"
  if [[ "${repo}" == "." ]]; then
    repo_label="flux"
  else
    repo_label="$(basename "${repo}")"
  fi

  echo "=== Preflight: ${repo_label} ==="
  git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    fail "${repo_label} is not a git worktree"

  branch="$(git -C "${dir}" branch --show-current)"
  [[ "${branch}" == "main" ]] || fail "${repo_label} is on '${branch}', not 'main'"

  [[ -z "$(git -C "${dir}" status --porcelain)" ]] || \
    fail "${repo_label} has uncommitted changes"

  description="${dir}/DESCRIPTION"
  [[ -f "${description}" ]] || fail "${repo_label} has no DESCRIPTION"
  actual_version="$(sed -n 's/^Version:[[:space:]]*//p' "${description}")"
  [[ "${actual_version}" == "${VERSION}" ]] || \
    fail "${repo_label} DESCRIPTION is ${actual_version}, expected ${VERSION}"

  local_head="$(git -C "${dir}" rev-parse HEAD)"
  set +e
  remote_main="$(git -C "${dir}" ls-remote origin refs/heads/main 2>/dev/null)"
  remote_main_status=$?
  set -e
  [[ ${remote_main_status} -eq 0 && -n "${remote_main}" ]] || \
    fail "could not verify origin/main for ${repo_label}"
  remote_head="${remote_main%%[[:space:]]*}"
  [[ "${local_head}" == "${remote_head}" ]] || \
    fail "${repo_label} HEAD is not synchronized with origin/main"

  if git -C "${dir}" rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null; then
    fail "${repo_label} already has local tag ${TAG}"
  fi

  set +e
  remote_tag="$(git -C "${dir}" ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null)"
  remote_status=$?
  set -e
  if [[ ${remote_status} -eq 0 && -n "${remote_tag}" ]]; then
    fail "${repo_label} already has remote tag ${TAG}"
  fi
  [[ ${remote_status} -eq 0 && -z "${remote_tag}" ]] || \
    fail "could not verify remote tag state for ${repo_label}"

  if [[ "${repo}" == "." ]]; then
    notes_file="${ROOT_DIR}/docs/release_announcements/${TAG}.md"
  else
    notes_file="${dir}/NEWS.md"
  fi
  [[ -f "${notes_file}" ]] || fail "missing release notes for ${repo_label}: ${notes_file}"
  if [[ "${repo}" != "." ]]; then
    grep -Fxq "## ${repo_label} ${VERSION}" "${notes_file}" || \
      fail "${notes_file} has no '## ${repo_label} ${VERSION}' section"
  fi

  if [[ ${CREATE_GH_RELEASE} -eq 1 ]]; then
    remote_url="$(git -C "${dir}" remote get-url origin)"
    repo_name="$(basename -s .git "${remote_url}")"
    set +e
    release_probe="$(gh release view "${TAG}" --repo "${OWNER}/${repo_name}" 2>&1)"
    release_status=$?
    set -e
    if [[ ${release_status} -eq 0 ]]; then
      fail "${repo_label} already has GitHub release ${TAG}"
    fi
    [[ "${release_probe}" == *"release not found"* ]] || \
      fail "could not verify GitHub release state for ${repo_label}: ${release_probe}"

    if [[ "${repo}" != "." ]]; then
      extract_news_section "${notes_file}" "${notes_dir}/${repo_label}-${VERSION}.md"
    fi
  fi

  echo "  version ${actual_version}; clean synchronized main; ${TAG} is available"
done

echo
echo "All repositories passed coordinated release preflight."

if [[ ${EXECUTE} -ne 1 ]]; then
  echo "Dry run complete; no commits, tags, pushes, or releases were created."
  exit 0
fi

# Pass 2 publishes the already-validated release candidates. Root remains last.
for repo in "${REPOS[@]}"; do
  dir="${ROOT_DIR}/${repo}"
  if [[ "${repo}" == "." ]]; then
    repo_label="flux"
  else
    repo_label="$(basename "${repo}")"
  fi

  echo
  echo "=== Release: ${repo_label} ==="
  git -C "${dir}" push origin HEAD
  git -C "${dir}" tag -a "${TAG}" -m "${TAG}"
  git -C "${dir}" push origin "${TAG}"

  if [[ ${CREATE_GH_RELEASE} -eq 1 ]]; then
    remote_url="$(git -C "${dir}" remote get-url origin)"
    repo_name="$(basename -s .git "${remote_url}")"
    if [[ "${repo}" == "." ]]; then
      notes_file="${ROOT_DIR}/docs/release_announcements/${TAG}.md"
      release_title="flux ${TAG}"
    else
      notes_file="${notes_dir}/${repo_label}-${VERSION}.md"
      release_title="${TAG}"
    fi

    gh release create "${TAG}" \
      --repo "${OWNER}/${repo_name}" \
      --title "${release_title}" \
      --notes-file "${notes_file}"
  fi
done

echo
echo "Coordinated ${TAG} release complete."
