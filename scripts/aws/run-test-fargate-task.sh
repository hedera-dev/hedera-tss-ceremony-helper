#!/usr/bin/env sh
# run-test-fargate-task.sh — Creates an ECS Fargate service for the test TSS ceremony.
#
# Usage:
#   ./scripts/aws/run-test-fargate-task.sh
#
# Environment variables:
#   AWS_REGION      AWS region (e.g. us-east-1)
#   PARTICIPANT_ID  Your participant ID (e.g. 1000000001)
#
# Requirements:
#   - AWS CLI authenticated via `aws configure` or environment variables.
#   - Run ./scripts/aws/setup-participant.sh once before using this script.
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
: "${AWS_REGION:?AWS_REGION is required}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ── Test ceremony parameters ──────────────────────────────────────────────────
PARTICIPANT_ID_PLUS_1=$((PARTICIPANT_ID + 1))
IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hedera-tss/hedera-tss-ceremony-helper:latest"
PARTICIPANT_IDS="1,2,1000000001"
S3_REGION="us-east1"
S3_ENDPOINT="https://storage.googleapis.com"
S3_BUCKET="tss-ceremony-testnet"
JAR_URL="https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar"

# ── Render the task definition template ───────────────────────────────────────
TMPFILE="$(mktemp /tmp/ecs-task-definition-XXXXXX.json)"
trap 'rm -f "${TMPFILE}"' EXIT

sed \
  -e "s|<PARTICIPANT_ID>|${PARTICIPANT_ID}|g" \
  -e "s|<PARTICIPANT_ID_PLUS_1>|${PARTICIPANT_ID_PLUS_1}|g" \
  -e "s|<IMAGE>|${IMAGE}|g" \
  -e "s|<PARTICIPANT_IDS>|${PARTICIPANT_IDS}|g" \
  -e "s|<S3_REGION>|${S3_REGION}|g" \
  -e "s|<S3_ENDPOINT>|${S3_ENDPOINT}|g" \
  -e "s|<S3_BUCKET>|${S3_BUCKET}|g" \
  -e "s|<AWS_REGION>|${AWS_REGION}|g" \
  -e "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" \
  -e "s|<JAR_URL>|${JAR_URL}|g" \
  "${SCRIPT_DIR}/ecs-task-definition.json.tpl" > "${TMPFILE}"

# ── Ensure the ECS cluster exists ─────────────────────────────────────────────
aws ecs create-cluster \
  --region "${AWS_REGION}" \
  --cluster-name hedera-tss \
  --output text > /dev/null 2>&1 || true

# ── Register the task definition ─────────────────────────────────────────────
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --region "${AWS_REGION}" \
  --cli-input-json "file://${TMPFILE}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "Registered task definition: ${TASK_DEF_ARN}"

# ── Resolve default VPC and a subnet ─────────────────────────────────────────
VPC_ID=$(aws ec2 describe-vpcs \
  --region "${AWS_REGION}" \
  --filters 'Name=is-default,Values=true' \
  --query 'Vpcs[0].VpcId' \
  --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
  --region "${AWS_REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" 'Name=default-for-az,Values=true' \
  --query 'Subnets[0].SubnetId' \
  --output text)

# ── Create or reuse the security group (outbound-only) ───────────────────────
SG_ID=$(aws ec2 describe-security-groups \
  --region "${AWS_REGION}" \
  --filters "Name=group-name,Values=hedera-tss-ceremony" "Name=vpc-id,Values=${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

if [ -z "${SG_ID}" ] || [ "${SG_ID}" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group \
    --region "${AWS_REGION}" \
    --group-name hedera-tss-ceremony \
    --description "Hedera TSS Ceremony - outbound only" \
    --vpc-id "${VPC_ID}" \
    --query 'GroupId' \
    --output text)
  # Remove the default inbound rule allowing all traffic (if present) by
  # revoking the default egress all-allow — outbound access is kept as-is
  # (Fargate requires outbound to reach ECR, GitHub, and GCS).
fi

# ── Create or update the ECS service ─────────────────────────────────────────
SERVICE_STATUS=$(aws ecs describe-services \
  --region "${AWS_REGION}" \
  --cluster hedera-tss \
  --services "hedera-tss-ceremony-${PARTICIPANT_ID}" \
  --query 'services[0].status' \
  --output text 2>/dev/null || echo "MISSING")

if [ "${SERVICE_STATUS}" = "ACTIVE" ]; then
  echo "Updating existing service with new task definition..."
  aws ecs update-service \
    --region "${AWS_REGION}" \
    --cluster hedera-tss \
    --service "hedera-tss-ceremony-${PARTICIPANT_ID}" \
    --task-definition "${TASK_DEF_ARN}" \
    --force-new-deployment \
    --output table
else
  echo "Creating new ECS service..."
  aws ecs create-service \
    --region "${AWS_REGION}" \
    --cluster hedera-tss \
    --service-name "hedera-tss-ceremony-${PARTICIPANT_ID}" \
    --task-definition "${TASK_DEF_ARN}" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --output table
fi
