#!/bin/bash
# gce-startup.sh.tpl — Template for the GCE startup script.
#
# DO NOT execute or edit this file directly. Use the wrapper scripts instead:
#   scripts/gcp/create-test-instance.sh   — test ceremony
#   scripts/gcp/create-instance.sh        — production ceremony
#
# Those scripts substitute the <...> placeholders and pass the rendered script
# to `gcloud compute instances create` automatically.
#
# The rendered script is executed on every boot of the GCE instance: it fetches
# S3 credentials and node key/certificate from GCP Secret Manager, then pulls
# and starts the ceremony container.
#
set -eu

# ── Variables ─────────────────────────────────────────────────────────────────
NODE_ID=<NODE_ID>
NODE_ID_PLUS_1=$((NODE_ID + 1))
IMAGE="<IMAGE>"
NODE_IDS="<NODE_IDS>"
S3_REGION="<S3_REGION>"
S3_ENDPOINT="<S3_ENDPOINT>"
S3_BUCKET="<S3_BUCKET>"
JAR_URL="<JAR_URL>"

# COS does not ship gcloud. Derive project and token from the metadata server,
# and use the Secret Manager REST API directly via curl + python3.
GCP_PROJECT_ID=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/project/project-id")
REGISTRY="${IMAGE%%/*}"
TOKEN=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

# Helper: fetch and base64-decode a Secret Manager secret.
get_secret() {
  curl -sf \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}/secrets/${1}/versions/latest:access" \
  | python3 -c "import sys, json, base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode(), end='')"
}

# ── Fetch S3 credentials from Secret Manager ──────────────────────────────────
ACCESS_KEY=$(get_secret "tss-s3-access-key-${NODE_ID}")
SECRET_KEY=$(get_secret "tss-s3-secret-key-${NODE_ID}")

# ── Fetch node key and certificate from Secret Manager ────────────────────────
mkdir -p /var/tss/keys
get_secret "tss-node-private-key-${NODE_ID}" > "/var/tss/keys/s-private-node${NODE_ID_PLUS_1}.pem"
get_secret "tss-node-public-cert-${NODE_ID}" > "/var/tss/keys/s-public-node${NODE_ID_PLUS_1}.pem"
chmod 600 /var/tss/keys/*.pem
chown -R 1000:1000 /var/tss/keys

# ── Pull and run the ceremony container ───────────────────────────────────────
# Remove any existing container from a previous boot (startup script runs on every boot).
# Use a temporary Docker config dir so the token is never written to disk.
mkdir -p /var/tss/logs
chown 1000:1000 /var/tss/logs
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "${DOCKER_CONFIG}"' EXIT
echo "${TOKEN}" | docker --config "${DOCKER_CONFIG}" login \
  --username=oauth2accesstoken --password-stdin "${REGISTRY}"
docker rm -f hedera-tss-ceremony 2>/dev/null || true
docker --config "${DOCKER_CONFIG}" pull --platform linux/amd64 "${IMAGE}"
docker run -d \
  --platform linux/amd64 \
  --name hedera-tss-ceremony \
  --restart=on-failure \
  -e TSS_CEREMONY_S3_ACCESS_KEY="${ACCESS_KEY}" \
  -e TSS_CEREMONY_S3_SECRET_KEY="${SECRET_KEY}" \
  -e JAR_URL="${JAR_URL}" \
  -e RUST_BACKTRACE=full \
  -v /var/tss/keys:/app/keys:ro \
  -v /var/tss/logs:/app/logs \
  "${IMAGE}" \
  "${NODE_ID}" \
  "${NODE_IDS}" \
  "${S3_REGION}" \
  "${S3_ENDPOINT}" \
  "${S3_BUCKET}" \
  /app/keys/ \
  password
