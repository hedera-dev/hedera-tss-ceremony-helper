#!/usr/bin/env sh
# create-test-instance.sh — Creates an EC2 instance for the test TSS ceremony.
#
# Usage:
#   ./scripts/aws/create-test-instance.sh
#
# Environment variables:
#   AWS_REGION      AWS region (e.g. us-east-1)
#   PARTICIPANT_ID  Your participant ID (e.g. 1000000001)
#
# Requirements: AWS CLI authenticated via `aws configure` or environment variables.
# The IAM instance profile `hedera-tss-instance-profile` must already exist (see README).
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
IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hedera-tss/hedera-tss-ceremony-helper:latest"
PARTICIPANT_IDS="1000000001,1000000002,1000000003,1000000004,1000000005,1000000006,1000000007,1000000008,1000000009,1000000010,1000000011,1000000012,1000000013,1000000014,1000000015,1000000016,1000000017,1000000018,1000000019,1000000020"
S3_REGION="us-east1"
S3_ENDPOINT="https://storage.googleapis.com"
S3_BUCKET="tss-ceremony-testnet"
JAR_URL="${JAR_URL:-https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar}"
: "${JAR_HASH:?JAR_HASH is required (expected SHA-256 hash of the JAR)}"

# ── Render the user data template ─────────────────────────────────────────────
TMPFILE="$(mktemp /tmp/ec2-userdata-XXXXXX.sh)"
trap 'rm -f "${TMPFILE}"' EXIT

sed \
  -e "s|<PARTICIPANT_ID>|${PARTICIPANT_ID}|g" \
  -e "s|<IMAGE>|${IMAGE}|g" \
  -e "s|<PARTICIPANT_IDS>|${PARTICIPANT_IDS}|g" \
  -e "s|<S3_REGION>|${S3_REGION}|g" \
  -e "s|<S3_ENDPOINT>|${S3_ENDPOINT}|g" \
  -e "s|<S3_BUCKET>|${S3_BUCKET}|g" \
  -e "s|<AWS_REGION>|${AWS_REGION}|g" \
  -e "s|<AWS_ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" \
  -e "s|<JAR_URL>|${JAR_URL}|g" \
  -e "s|<JAR_HASH>|${JAR_HASH}|g" \
  -e "s|<RESTART_POLICY>|no|g" \
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

# ── Check for an existing instance ───────────────────────────────────────────
EXISTING_ID=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=hedera-tss-ceremony-${PARTICIPANT_ID}" \
    'Name=instance-state-name,Values=pending,running,stopping,stopped' \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

print_instance_info() {
  echo "Instance ID: $1"
  echo ""
  echo "To view the logs, run the following command:"
  echo ""
  echo "  aws logs get-log-events \\"
  echo "    --region \"${AWS_REGION}\" \\"
  echo "    --log-group-name /hedera-tss-ceremony \\"
  echo "    --log-stream-name \"participant-${PARTICIPANT_ID}\" \\"
  echo "    --no-cli-pager"
  echo ""
  echo "Or check the logs in real-time via SSM Session Manager (no inbound ports required):"
  echo ""
  echo "  export INSTANCE_ID=$1"
  echo "  aws ssm start-session \\"
  echo "    --region \"${AWS_REGION}\" \\"
  echo "    --target \"${INSTANCE_ID}\" \\"
  echo "    --document-name AWS-StartInteractiveCommand \\"
  echo "    --parameters 'command=[\"sudo docker logs -f hedera-tss-ceremony\"]'"
}

if [ "${EXISTING_ID}" != "None" ] && [ -n "${EXISTING_ID}" ]; then
  echo "An instance for participant ${PARTICIPANT_ID} already exists: ${EXISTING_ID}"
  printf "Terminate it and create a new one? [y/N] "
  read -r ANSWER
  case "${ANSWER}" in
    y|Y)
      echo "==> Terminating ${EXISTING_ID}..."
      aws ec2 terminate-instances \
        --region "${AWS_REGION}" \
        --instance-ids "${EXISTING_ID}" \
        --no-cli-pager > /dev/null
      echo "    Waiting for termination..."
      aws ec2 wait instance-terminated \
        --region "${AWS_REGION}" \
        --instance-ids "${EXISTING_ID}" \
        --no-cli-pager
      ;;
    *)
      print_instance_info "${EXISTING_ID}"
      exit 0
      ;;
  esac
fi

# ── Create the EC2 instance ───────────────────────────────────────────────────
INSTANCE_ID=$(aws ec2 run-instances \
  --region "${AWS_REGION}" \
  --image-id "${AMI_ID}" \
  --instance-type m6i.xlarge \
  --iam-instance-profile Name=hedera-tss-instance-profile \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":60,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=hedera-tss-ceremony-${PARTICIPANT_ID}}]" \
  --user-data "file://${TMPFILE}" \
  --query 'Instances[0].InstanceId' \
  --output text)

print_instance_info "${INSTANCE_ID}"