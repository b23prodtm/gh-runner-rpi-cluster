#!/bin/bash
# scripts/update_templates.sh
#
# Reference implementation of the substitution step this project expects
# from the `balena-cloud-apps` package's `update_templates` command.
#
# Real usage: update_templates <project_root|/opt/local/bin/update_templates> [options]
# It takes ONLY a project_root — every $(BALENA_ARCH).env file found next to
# common.env is processed in sequence, one after another, in the same run.
# This fallback mirrors that: no target argument, all archs rendered.
#
# Usage: ./scripts/update_templates.sh <project_root>
#   e.g. ./scripts/update_templates.sh .
#
# Output layout: each arch gets its own self-contained build context under
# build/<arch>/ (Dockerfile + entrypoint.sh + docker-compose.yml), so the 3
# archs never overwrite each other's rendered files.

set -euo pipefail

PROJECT_ROOT="${1:?Usage: update_templates.sh <project_root> (e.g. .)}"
ROOT_DIR="$(cd "$PROJECT_ROOT" && pwd)"
COMMON_ENV="${ROOT_DIR}/common.env"

[ -f "$COMMON_ENV" ] || { echo "Missing common.env in ${ROOT_DIR}"; exit 1; }

render_arch() {
  local arch_env="$1"
  local arch
  arch="$(basename "$arch_env" .env)"
  local build_dir="${ROOT_DIR}/build/${arch}"

  mkdir -p "${build_dir}/gh-runner"

  # Fresh env per arch: common.env first, then this arch's overrides.
  set -a
  # shellcheck disable=SC1090
  source "$COMMON_ENV"
  # shellcheck disable=SC1090
  source "$arch_env"
  set +a

  render() {
    local template="$1"
    local output="$2"
    local content
    content="$(cat "$template")"
    for key in $(grep -oE '%%[A-Z_]+%%' "$template" | tr -d '%' | sort -u); do
      local value="${!key:-}"
      content="${content//%%${key}%%/${value}}"
    done
    echo "$content" > "$output"
  }

  render "${ROOT_DIR}/docker-compose.yml.template" "${build_dir}/docker-compose.yml"
  render "${ROOT_DIR}/gh-runner/Dockerfile.template" "${build_dir}/gh-runner/Dockerfile"
  cp "${ROOT_DIR}/gh-runner/entrypoint.sh" "${build_dir}/gh-runner/entrypoint.sh"

  echo "Rendered: build/${arch}/ (arch=${arch})"
}

# Process every $(BALENA_ARCH).env found next to common.env, in sequence.
for arch_env in "${ROOT_DIR}"/*.env; do
  [ "$(basename "$arch_env")" = "common.env" ] && continue
  render_arch "$arch_env"
done
