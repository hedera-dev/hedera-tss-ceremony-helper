#!/bin/bash
# ec2-userdata.sh.tpl — EC2 user data template for the Hedera TSS Ceremony Helper.
#
# DO NOT execute or edit this file directly. Use the wrapper scripts instead:
#   scripts/aws/create-test-instance.sh   — test ceremony
#   scripts/aws/create-instance.sh        — production ceremony
#
# Those scripts substitute the <...> placeholders and pass the rendered script
# to `aws ec2 run-instances` via --user-data automatically.
#
# The rendered script is executed on first boot of the EC2 instance: it installs
# Docker, fetches S3 credentials and participant key/certificate from AWS Secrets
# Manager, then pulls and starts the ceremony container.
#
set -eu

# ── Install Docker ────────────────────────────────────────────────────────────
dnf install -y docker
systemctl enable --now docker

# ── Variables ─────────────────────────────────────────────────────────────────
PARTICIPANT_ID=<PARTICIPANT_ID>
PARTICIPANT_ID_PLUS_1=$((PARTICIPANT_ID + 1))
IMAGE="<IMAGE>"
PARTICIPANT_IDS="<PARTICIPANT_IDS>"
S3_REGION="<S3_REGION>"
S3_ENDPOINT="<S3_ENDPOINT>"
S3_BUCKET="<S3_BUCKET>"
AWS_REGION="<AWS_REGION>"
AWS_ACCOUNT_ID="<AWS_ACCOUNT_ID>"
JAR_URL="<JAR_URL>"
JAR_HASH="<JAR_HASH>"

# ── Fetch S3 credentials from Secrets Manager ─────────────────────────────────
ACCESS_KEY=$(aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "tss-s3-access-key-${PARTICIPANT_ID}" \
  --query SecretString --output text)
SECRET_KEY=$(aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "tss-s3-secret-key-${PARTICIPANT_ID}" \
  --query SecretString --output text)

# ── Fetch participant key and certificate from Secrets Manager ───────────────────────
mkdir -p /var/tss/keys
aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "tss-participant-private-key-${PARTICIPANT_ID}" \
  --query SecretString --output text \
  > "/var/tss/keys/s-private-node${PARTICIPANT_ID_PLUS_1}.pem"
aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "tss-participant-public-cert-${PARTICIPANT_ID}" \
  --query SecretString --output text \
  > "/var/tss/keys/s-public-node${PARTICIPANT_ID_PLUS_1}.pem"
chmod 600 /var/tss/keys/*.pem
chown -R 1000:1000 /var/tss/keys

# ── Authenticate to ECR and start the ceremony container ──────────────────────
# Use a temporary Docker config dir so the token is never written to disk.
mkdir -p /var/tss/logs
chown 1000:1000 /var/tss/logs
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "${DOCKER_CONFIG}"' EXIT
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker --config "${DOCKER_CONFIG}" login --username AWS --password-stdin \
  "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker --config "${DOCKER_CONFIG}" pull "${IMAGE}"
docker run -d \
  --name hedera-tss-ceremony \
  --restart=<RESTART_POLICY> \
  -e TSS_CEREMONY_S3_ACCESS_KEY="${ACCESS_KEY}" \
  -e TSS_CEREMONY_S3_SECRET_KEY="${SECRET_KEY}" \
  -e JAR_URL="${JAR_URL}" \
  -e JAR_HASH="${JAR_HASH}" \
  -e RUST_BACKTRACE=full \
  -v /var/tss/keys:/app/keys:ro \
  -v /var/tss/logs:/app/logs \
  --log-driver=awslogs \
  --log-opt awslogs-region="${AWS_REGION}" \
  --log-opt awslogs-group=/hedera-tss-ceremony \
  --log-opt awslogs-stream="participant-${PARTICIPANT_ID}" \
  --log-opt awslogs-create-group=true \
  "${IMAGE}" \
  "${PARTICIPANT_ID}" \
  "${PARTICIPANT_IDS}" \
  "${S3_REGION}" \
  "${S3_ENDPOINT}" \
  "${S3_BUCKET}" \
  /app/keys/ \
  password
