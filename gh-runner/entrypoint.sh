#!/bin/bash
set -e

: "${GH_OWNER:?GH_OWNER must be set (Fleet/Device variable)}"
: "${GH_REPO:?GH_REPO must be set (Fleet/Device variable)}"
: "${GH_PAT:?GH_PAT must be set (Fleet/Device variable) - fine-grained PAT with administration:write}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)-$(cat /proc/sys/kernel/random/uuid | cut -c1-8)}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,ARM64,rpi,balena}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"

echo "Requesting a fresh registration token from the GitHub API..."
RUNNER_TOKEN=$(curl -sX POST \
  -H "Authorization: Bearer ${GH_PAT}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token" \
  | jq -r .token)

if [ -z "${RUNNER_TOKEN}" ] || [ "${RUNNER_TOKEN}" = "null" ]; then
  echo "ERROR: failed to obtain a registration token. Check GH_PAT permissions."
  exit 1
fi

./config.sh \
  --url "https://github.com/${GH_OWNER}/${GH_REPO}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --work "${RUNNER_WORKDIR}" \
  --labels "${RUNNER_LABELS}" \
  --ephemeral \
  --unattended \
  --replace

cleanup() {
  echo "Deregistering runner ${RUNNER_NAME}..."
  DEREG_TOKEN=$(curl -sX POST \
    -H "Authorization: Bearer ${GH_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/remove-token" \
    | jq -r .token)
  ./config.sh remove --unattended --token "${DEREG_TOKEN}" || true
}
trap cleanup EXIT INT TERM

./run.sh
