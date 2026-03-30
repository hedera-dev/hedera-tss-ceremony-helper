#!/usr/bin/env sh
# create-test-instance.sh — Creates a GCE instance for the test TSS ceremony.
#
# Usage:
#   ./scripts/gcp/create-test-instance.sh
#
# Environment variables:
#   GCP_PROJECT_ID  GCP project ID
#   GCP_REGION      GCP region for Artifact Registry (e.g. us-central1)
#   GCP_ZONE        GCP zone for the VM (e.g. us-central1-a)
#   NODE_ID         Your node ID (e.g. 1000000001)
#
# Requirements: gcloud (Google Cloud SDK) authenticated with `gcloud auth login`.
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Environment ── NODE_ID ────────────────────────────────────────────────────
: "${NODE_ID:?NODE_ID is required (e.g. export NODE_ID=1000000001)}"

if [ "$NODE_ID" -lt 1000000001 ] || [ "$NODE_ID" -gt 1000000020 ]; then
  echo "Error: NODE_ID must be between 1000000001 and 1000000020 (got: $NODE_ID)."
  exit 1
fi

# ── Environment ───────────────────────────────────────────────────────────────
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${GCP_ZONE:?GCP_ZONE is required}"

# ── Test ceremony parameters ──────────────────────────────────────────────────
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/hedera-tss/hedera-tss-ceremony-helper:latest"
NODE_IDS="1,2,1000000001"
S3_REGION="us-east1"
S3_ENDPOINT="https://storage.googleapis.com"
S3_BUCKET="tss-ceremony-testnet"
JAR_URL="${JAR_URL:-https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar}"

# ── Check if instance already exists ─────────────────────────────────────────
if gcloud compute instances describe hedera-tss-ceremony-${NODE_ID} \
     --project="${GCP_PROJECT_ID}" --zone="${GCP_ZONE}" > /dev/null 2>&1; then
  printf "Instance 'hedera-tss-ceremony-${NODE_ID}' already exists. Delete and recreate it? [y/N] "
  read -r REPLY
  case "${REPLY}" in
    [yY]|[yY][eE][sS])
      echo "==> Deleting existing instance..."
      gcloud compute instances delete hedera-tss-ceremony-${NODE_ID} \
        --project="${GCP_PROJECT_ID}" --zone="${GCP_ZONE}" --quiet
      ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
fi

# ── Render the startup script template ───────────────────────────────────────
TMPFILE="$(mktemp /tmp/gce-startup-XXXXXX.sh)"
trap 'rm -f "${TMPFILE}"' EXIT

sed \
  -e "s|<NODE_ID>|${NODE_ID}|g" \
  -e "s|<IMAGE>|${IMAGE}|g" \
  -e "s|<NODE_IDS>|${NODE_IDS}|g" \
  -e "s|<S3_REGION>|${S3_REGION}|g" \
  -e "s|<S3_ENDPOINT>|${S3_ENDPOINT}|g" \
  -e "s|<S3_BUCKET>|${S3_BUCKET}|g" \
  -e "s|<JAR_URL>|${JAR_URL}|g" \
  "${SCRIPT_DIR}/gce-startup.sh.tpl" > "${TMPFILE}"

# ── Create the GCE instance ───────────────────────────────────────────────────
gcloud compute instances create hedera-tss-ceremony-${NODE_ID} \
  --project="${GCP_PROJECT_ID}" \
  --machine-type=e2-standard-4 \
  --zone="${GCP_ZONE}" \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=60GB \
  --boot-disk-type=pd-ssd \
  --service-account="hedera-tss-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --scopes=cloud-platform \
  --metadata-from-file="startup-script=${TMPFILE}"

echo "Instance 'hedera-tss-ceremony-${NODE_ID}' created successfully."
echo "Follow the logs with:"
echo ""
echo "gcloud compute ssh \"hedera-tss-ceremony-\${NODE_ID}\" --zone=\"\${GCP_ZONE}\" -- \\"
echo "  'docker logs -t hedera-tss-ceremony'"