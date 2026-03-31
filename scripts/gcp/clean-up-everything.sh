#!/usr/bin/env sh
# clean-up-everything.sh — Cleans up after the ceremony on GCP.
#
# This script removes:
#   1. The GCE instance (if it exists).
#   2. Key and credential secrets from GCP Secret Manager.
#
# Usage:
#   ./scripts/gcp/clean-up-everything.sh
#
# Environment variables:
#   GCP_PROJECT_ID  GCP project ID
#   GCP_ZONE        GCP zone for the VM (e.g. us-central1-a)
#   PARTICIPANT_ID  Your participant ID (e.g. 1000000001)
#
# Requirements:
#   - gcloud (Google Cloud SDK) authenticated with `gcloud auth login`.
#
set -eu

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_ZONE:?GCP_ZONE is required}"
: "${PARTICIPANT_ID:?PARTICIPANT_ID is required (e.g. export PARTICIPANT_ID=1000000001)}"

INSTANCE_NAME="hedera-tss-ceremony-${PARTICIPANT_ID}"
SECRETS="tss-s3-access-key-${PARTICIPANT_ID} tss-s3-secret-key-${PARTICIPANT_ID} tss-participant-private-key-${PARTICIPANT_ID} tss-participant-public-cert-${PARTICIPANT_ID}"

INSTANCE_EXISTS=false
if gcloud compute instances describe "${INSTANCE_NAME}" \
     --project="${GCP_PROJECT_ID}" --zone="${GCP_ZONE}" > /dev/null 2>&1; then
  INSTANCE_EXISTS=true
fi

echo "This will permanently delete the following GCP resources:"
echo ""
if [ "${INSTANCE_EXISTS}" = true ]; then
  echo "  GCE instance:"
  echo "    - ${INSTANCE_NAME} (will be deleted)"
  echo ""
fi
echo "  Secret Manager secrets:"
for s in ${SECRETS}; do
  echo "    - ${s}"
done
echo ""
printf "Are you sure? This action cannot be undone. [y/N] "
read -r REPLY
case "${REPLY}" in
  [yY]|[yY][eE][sS]) ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

# ── Delete the GCE instance ─────────────────────────────────────────────────
if [ "${INSTANCE_EXISTS}" = true ]; then
  echo "==> Deleting GCE instance ${INSTANCE_NAME}..."
  gcloud compute instances delete "${INSTANCE_NAME}" \
    --project="${GCP_PROJECT_ID}" \
    --zone="${GCP_ZONE}" \
    --quiet
  echo "   Instance deleted."
fi

# ── Delete secrets from Secret Manager ──────────────────────────────────────
echo "==> Deleting secrets from Secret Manager..."
for SECRET in ${SECRETS}; do
  gcloud secrets delete "${SECRET}" \
    --project="${GCP_PROJECT_ID}" \
    --quiet 2>/dev/null \
    && echo "   Deleted: ${SECRET}" \
    || echo "   Not found (already deleted?): ${SECRET}"
done

echo ""
echo "Done. All ceremony resources for participant ${PARTICIPANT_ID} have been removed from GCP."
