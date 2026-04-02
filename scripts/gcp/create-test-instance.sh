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
#   PARTICIPANT_ID  Your participant ID (e.g. 1000000001)
#
# Requirements: gcloud (Google Cloud SDK) authenticated with `gcloud auth login`.
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Environment ── PARTICIPANT_ID ────────────────────────────────────────────────────
: "${PARTICIPANT_ID:?PARTICIPANT_ID is required (e.g. export PARTICIPANT_ID=1000000001)}"

if [ "$PARTICIPANT_ID" -lt 1000000001 ] || [ "$PARTICIPANT_ID" -gt 1000000020 ]; then
  echo "Error: PARTICIPANT_ID must be between 1000000001 and 1000000020 (got: $PARTICIPANT_ID)."
  exit 1
fi

# ── Environment ───────────────────────────────────────────────────────────────
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${GCP_ZONE:?GCP_ZONE is required}"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/hedera-tss/hedera-tss-ceremony-helper:latest"

# ── Test ceremony parameters ──────────────────────────────────────────────────
PARTICIPANT_IDS="1000000001,1000000002,1000000003,1000000004,1000000005,1000000006,1000000007,1000000008,1000000009,1000000010,1000000011,1000000012,1000000013,1000000014,1000000015,1000000016,1000000017,1000000018,1000000019,1000000020"
S3_REGION="us-east1"
S3_ENDPOINT="https://storage.googleapis.com"
S3_BUCKET="tss-ceremony-mainnet"
JAR_URL="${JAR_URL:-https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar}"
JAR_HASH="${JAR_HASH:-786e87f95d4f1d84550e377c0e47930388a3d96afd8b5f56a544b2efee2a650a}"

# ── Check if instance already exists ─────────────────────────────────────────
if gcloud compute instances describe hedera-tss-ceremony-${PARTICIPANT_ID} \
     --project="${GCP_PROJECT_ID}" --zone="${GCP_ZONE}" > /dev/null 2>&1; then
  printf "Instance 'hedera-tss-ceremony-${PARTICIPANT_ID}' already exists. Delete and recreate it? [y/N] "
  read -r REPLY
  case "${REPLY}" in
    [yY]|[yY][eE][sS])
      echo "==> Deleting existing instance..."
      gcloud compute instances delete hedera-tss-ceremony-${PARTICIPANT_ID} \
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
  -e "s|<PARTICIPANT_ID>|${PARTICIPANT_ID}|g" \
  -e "s|<IMAGE>|${IMAGE}|g" \
  -e "s|<PARTICIPANT_IDS>|${PARTICIPANT_IDS}|g" \
  -e "s|<S3_REGION>|${S3_REGION}|g" \
  -e "s|<S3_ENDPOINT>|${S3_ENDPOINT}|g" \
  -e "s|<S3_BUCKET>|${S3_BUCKET}|g" \
  -e "s|<JAR_URL>|${JAR_URL}|g" \
  -e "s|<JAR_HASH>|${JAR_HASH}|g" \
  "${SCRIPT_DIR}/gce-startup.sh.tpl" > "${TMPFILE}"

# ── Create the GCE instance ───────────────────────────────────────────────────
echo "Creating GCE instance 'hedera-tss-ceremony-${PARTICIPANT_ID}' in project '${GCP_PROJECT_ID}', zone '${GCP_ZONE}'..."
gcloud compute instances create hedera-tss-ceremony-${PARTICIPANT_ID} \
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

echo "Instance 'hedera-tss-ceremony-${PARTICIPANT_ID}' created successfully."
echo "Wait a few moments for the instance to initialize, then follow the logs with:"
echo ""
echo "gcloud compute ssh \"hedera-tss-ceremony-\${PARTICIPANT_ID}\" --zone=\"\${GCP_ZONE}\" -- \\"
echo "  'docker logs -t hedera-tss-ceremony'"