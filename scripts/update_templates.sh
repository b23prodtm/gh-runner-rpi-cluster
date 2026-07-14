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
# Output layout: rendered files are written at the project root as
# docker-compose.<arch> and gh-runner/Dockerfile.<arch>.

set -euo pipefail

PROJECT_ROOT="${1:?Usage: update_templates.sh <project_root> (e.g. .)}"
ROOT_DIR="$(cd "$PROJECT_ROOT" && pwd)"
COMMON_ENV="${ROOT_DIR}/common.env"

[ -f "$COMMON_ENV" ] || { echo "Missing common.env in ${ROOT_DIR}"; exit 1; }

render_arch() {
  local arch_env="$1"
  local arch
  arch="$(basename "$arch_env" .env)"
  local compose_output="${ROOT_DIR}/docker-compose.${arch}"
  local dockerfile_output="${ROOT_DIR}/gh-runner/Dockerfile.${arch}"

  # Fresh env per arch: common.env first, then this arch's overrides.
  set -a
  OUTPUT_ARCH="$arch"
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

  render "${ROOT_DIR}/docker-compose.yml.template" "${compose_output}"
  render "${ROOT_DIR}/gh-runner/Dockerfile.template" "${dockerfile_output}"

  echo "Rendered: docker-compose.${arch}, gh-runner/Dockerfile.${arch} (arch=${arch})"
}

# Process every $(BALENA_ARCH).env found next to common.env, in sequence.
for arch_env in "${ROOT_DIR}"/*.env; do
  [ "$(basename "$arch_env")" = "common.env" ] && continue
  render_arch "$arch_env"
done
