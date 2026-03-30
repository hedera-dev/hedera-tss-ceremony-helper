#!/usr/bin/env sh
# create-test-instance.sh — Creates an EC2 instance for the test TSS ceremony.
#
# Usage:
#   ./scripts/aws/create-test-instance.sh
#
# Environment variables:
#   AWS_REGION  AWS region (e.g. us-east-1)
#   NODE_ID     Your node ID (e.g. 1000000001)
#
# Requirements: AWS CLI authenticated via `aws configure` or environment variables.
# The IAM instance profile `hedera-tss-instance-profile` must already exist (see README).
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
: "${AWS_REGION:?AWS_REGION is required}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ── Test ceremony parameters ──────────────────────────────────────────────────
IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hedera-tss/hedera-tss-ceremony-helper:latest"
NODE_IDS="1,2,1000000001"
S3_REGION="us-east1"
S3_ENDPOINT="https://storage.googleapis.com"
S3_BUCKET="tss-ceremony-testnet"
JAR_URL="${JAR_URL:-https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar}"

# ── Render the user data template ─────────────────────────────────────────────
TMPFILE="$(mktemp /tmp/ec2-userdata-XXXXXX.sh)"
trap 'rm -f "${TMPFILE}"' EXIT

sed \
  -e "s|<NODE_ID>|${NODE_ID}|g" \
  -e "s|<IMAGE>|${IMAGE}|g" \
  -e "s|<NODE_IDS>|${NODE_IDS}|g" \
  -e "s|<S3_REGION>|${S3_REGION}|g" \
  -e "s|<S3_ENDPOINT>|${S3_ENDPOINT}|g" \
  -e "s|<S3_BUCKET>|${S3_BUCKET}|g" \
  -e "s|<AWS_REGION>|${AWS_REGION}|g" \
  -e "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" \
  -e "s|<JAR_URL>|${JAR_URL}|g" \
  "${SCRIPT_DIR}/ec2-userdata.sh.tpl" > "${TMPFILE}"

# ── Resolve the latest Amazon Linux 2023 x86_64 AMI ──────────────────────────
AMI_ID=$(aws ec2 describe-images \
  --region "${AWS_REGION}" \
  --owners amazon \
  --filters \
    'Name=name,Values=al2023-ami-2023.*-kernel-*-x86_64' \
    'Name=state,Values=available' \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Using AMI: ${AMI_ID}"

# ── Create the EC2 instance ───────────────────────────────────────────────────
aws ec2 run-instances \
  --region "${AWS_REGION}" \
  --image-id "${AMI_ID}" \
  --instance-type m6i.xlarge \
  --iam-instance-profile Name=hedera-tss-instance-profile \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":60,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=hedera-tss-ceremony-${NODE_ID}}]" \
  --user-data "file://${TMPFILE}" \
  --output table
