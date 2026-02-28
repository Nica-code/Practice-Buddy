#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="practicebuddytracker"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PRESERVE_EMAILS="nicaviolin@icloud.com"

# Deletes test Firestore collections used by the app while preserving master users.
# Run from repo root: ./scripts/firestore_launch_reset.sh

SERVICE_ACCOUNT_PATH="${SERVICE_ACCOUNT_PATH:-}"
PRESERVE_UIDS="${PRESERVE_UIDS:-}"
PRESERVE_EMAILS="${PRESERVE_EMAILS:-$DEFAULT_PRESERVE_EMAILS}"

echo "Running launch reset for ${PROJECT_ID}"
echo "Preserved emails: ${PRESERVE_EMAILS}"
if [[ -n "${PRESERVE_UIDS}" ]]; then
  echo "Preserved UIDs: ${PRESERVE_UIDS}"
fi

NODE_SCRIPT="${REPO_ROOT}/functions/scripts/firestore_launch_reset_preserve_master.js"
if [[ ! -f "${NODE_SCRIPT}" ]]; then
  echo "Missing reset script at ${NODE_SCRIPT}"
  exit 1
fi

ARGS=(
  --project "${PROJECT_ID}"
  --preserve-emails "${PRESERVE_EMAILS}"
)

if [[ -n "${PRESERVE_UIDS}" ]]; then
  ARGS+=(--preserve-uids "${PRESERVE_UIDS}")
fi

if [[ -n "${SERVICE_ACCOUNT_PATH}" ]]; then
  ARGS+=(--service-account "${SERVICE_ACCOUNT_PATH}")
fi

cd "${REPO_ROOT}/functions"
node "./scripts/firestore_launch_reset_preserve_master.js" "${ARGS[@]}"

echo "Firestore launch reset complete for ${PROJECT_ID}."
echo "Next: delete only test Authentication users in Firebase Console (Auth -> Users), keep your master account."
