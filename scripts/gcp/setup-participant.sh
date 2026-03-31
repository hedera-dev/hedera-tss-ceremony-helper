#!/usr/bin/env sh
# setup.sh — One-time GCP resource setup for the Hedera TSS Ceremony Helper.
#
# Run this script once before creating the GCE instance. It is idempotent
# and safe to run again if any step was previously completed.
#
# Required environment variables (set once in your shell profile):
#   GCP_PROJECT_ID             GCP project ID
#   GCP_REGION                 GCP region for Artifact Registry (e.g. us-central1)
#   PARTICIPANT_ID             Your participant ID (e.g. 1000000001)
#   TSS_CEREMONY_S3_ACCESS_KEY GCP S3 access key for the ceremony bucket
#   TSS_CEREMONY_S3_SECRET_KEY GCP S3 secret key for the ceremony bucket
#
# Requirements: gcloud (Google Cloud SDK) authenticated with `gcloud auth login`.
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

# ── Environment ───────────────────────────────────────────────────────────────
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${PARTICIPANT_ID:?PARTICIPANT_ID is required}"
: "${TSS_CEREMONY_S3_ACCESS_KEY:?TSS_CEREMONY_S3_ACCESS_KEY is required}"
: "${TSS_CEREMONY_S3_SECRET_KEY:?TSS_CEREMONY_S3_SECRET_KEY is required}"

PARTICIPANT_ID_PLUS_1=$((PARTICIPANT_ID + 1))

# ── Enable required APIs ───────────────────────────────────────────────────────
echo "==> Enabling required GCP APIs..."
gcloud services enable \
  --project="${GCP_PROJECT_ID}" \
  artifactregistry.googleapis.com \
  compute.googleapis.com \
  secretmanager.googleapis.com

# ── Create Artifact Registry repository ───────────────────────────────────────
echo "==> Creating Artifact Registry repository..."
gcloud artifacts repositories create hedera-tss \
  --project="${GCP_PROJECT_ID}" \
  --repository-format=docker \
  --location="${GCP_REGION}" 2>/dev/null \
  || echo "   (repository already exists — skipping)"

# ── Build the container image ─────────────────────────────────────────────────
echo "==> Building container image..."
"${REPO_ROOT}/scripts/build-oci-image.sh"

# ── Push the image to Artifact Registry ───────────────────────────────────────
echo "==> Authenticating Podman to Artifact Registry..."
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/hedera-tss/hedera-tss-ceremony-helper:latest"
echo "==> Pushing image to ${IMAGE}..."
podman manifest push hedera-tss-ceremony-helper:latest "${IMAGE}"

# ── Store S3 credentials in Secret Manager ────────────────────────────────────
echo "==> Storing S3 credentials in Secret Manager..."
printf '%s' "${TSS_CEREMONY_S3_ACCESS_KEY}" | \
  gcloud secrets create "tss-s3-access-key-${PARTICIPANT_ID}" \
    --project="${GCP_PROJECT_ID}" --data-file=- 2>/dev/null \
  || printf '%s' "${TSS_CEREMONY_S3_ACCESS_KEY}" | \
     gcloud secrets versions add "tss-s3-access-key-${PARTICIPANT_ID}" \
       --project="${GCP_PROJECT_ID}" --data-file=-

printf '%s' "${TSS_CEREMONY_S3_SECRET_KEY}" | \
  gcloud secrets create "tss-s3-secret-key-${PARTICIPANT_ID}" \
    --project="${GCP_PROJECT_ID}" --data-file=- 2>/dev/null \
  || printf '%s' "${TSS_CEREMONY_S3_SECRET_KEY}" | \
     gcloud secrets versions add "tss-s3-secret-key-${PARTICIPANT_ID}" \
       --project="${GCP_PROJECT_ID}" --data-file=-

# ── Store participant key and certificate in Secret Manager ─────────────────────────
echo "==> Storing participant key and certificate in Secret Manager..."
gcloud secrets create "tss-participant-private-key-${PARTICIPANT_ID}" \
  --project="${GCP_PROJECT_ID}" \
  --data-file="./keys/s-private-node${PARTICIPANT_ID_PLUS_1}.pem" 2>/dev/null \
  || gcloud secrets versions add "tss-participant-private-key-${PARTICIPANT_ID}" \
       --project="${GCP_PROJECT_ID}" \
       --data-file="./keys/s-private-node${PARTICIPANT_ID_PLUS_1}.pem"

gcloud secrets create "tss-participant-public-cert-${PARTICIPANT_ID}" \
  --project="${GCP_PROJECT_ID}" \
  --data-file="./keys/s-public-node${PARTICIPANT_ID_PLUS_1}.pem" 2>/dev/null \
  || gcloud secrets versions add "tss-participant-public-cert-${PARTICIPANT_ID}" \
       --project="${GCP_PROJECT_ID}" \
       --data-file="./keys/s-public-node${PARTICIPANT_ID_PLUS_1}.pem"

# ── Create service account ────────────────────────────────────────────────────
echo "==> Creating service account..."
gcloud iam service-accounts create hedera-tss-sa \
  --project="${GCP_PROJECT_ID}" \
  --display-name="Hedera TSS Ceremony SA" 2>/dev/null \
  || echo "   (service account already exists — skipping)"

SA_EMAIL="hedera-tss-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# ── Grant secret access to the service account ───────────────────────────────
echo "==> Granting Secret Manager access to service account..."
for SECRET in "tss-s3-access-key-${PARTICIPANT_ID}" "tss-s3-secret-key-${PARTICIPANT_ID}" "tss-participant-private-key-${PARTICIPANT_ID}" "tss-participant-public-cert-${PARTICIPANT_ID}"; do
  gcloud secrets add-iam-policy-binding "${SECRET}" \
    --project="${GCP_PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet
done

# ── Grant Artifact Registry read access to the service account ───────────────
echo "==> Granting Artifact Registry read access to service account..."
gcloud artifacts repositories add-iam-policy-binding hedera-tss \
  --project="${GCP_PROJECT_ID}" \
  --location="${GCP_REGION}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.reader" \
  --quiet

echo ""
echo "==> GCP setup complete. You can now create the GCE instance:"
echo ""
echo "    ./scripts/gcp/create-test-instance.sh"
echo ""
