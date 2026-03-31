#!/usr/bin/env sh
# clean-up-everything.sh — Cleans up after the ceremony on AWS.
#
# This script removes:
#   1. The EC2 instance (if INSTANCE_ID is set).
#   2. Key and credential secrets from AWS Secrets Manager.
#
# Usage:
#   ./scripts/aws/clean-up-everything.sh
#
# Environment variables:
#   AWS_REGION      AWS region (e.g. us-east-1)
#   PARTICIPANT_ID  Your participant ID (e.g. 1000000001)
#   INSTANCE_ID     (optional) EC2 instance ID — if set, the instance is
#                   terminated. If unset, only Secrets Manager secrets are removed.
#
# Requirements:
#   - AWS CLI authenticated via `aws configure` or environment variables.
#
set -eu

: "${AWS_REGION:?AWS_REGION is required}"
: "${PARTICIPANT_ID:?PARTICIPANT_ID is required (e.g. export PARTICIPANT_ID=1000000001)}"

SECRETS="tss-s3-access-key-${PARTICIPANT_ID} tss-s3-secret-key-${PARTICIPANT_ID} tss-participant-private-key-${PARTICIPANT_ID} tss-participant-public-cert-${PARTICIPANT_ID}"

echo "This will permanently delete the following AWS resources:"
echo ""
if [ -n "${INSTANCE_ID:-}" ]; then
  echo "  EC2 instance:"
  echo "    - ${INSTANCE_ID} (will be terminated)"
  echo ""
fi
echo "  Secrets Manager secrets:"
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

# ── Terminate the EC2 instance ───────────────────────────────────────────────
if [ -n "${INSTANCE_ID:-}" ]; then
  echo "==> Terminating EC2 instance ${INSTANCE_ID}..."
  aws ec2 terminate-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --output text > /dev/null
  echo "   Instance ${INSTANCE_ID} is being terminated."
fi

# ── Delete secrets from Secrets Manager ─────────────────────────────────────
echo "==> Deleting secrets from Secrets Manager..."
for SECRET in ${SECRETS}; do
  aws secretsmanager delete-secret \
    --region "${AWS_REGION}" \
    --secret-id "${SECRET}" \
    --force-delete-without-recovery \
    --output text > /dev/null 2>&1 \
    && echo "   Deleted: ${SECRET}" \
    || echo "   Not found (already deleted?): ${SECRET}"
done

echo ""
echo "Done. All ceremony resources for participant ${PARTICIPANT_ID} have been removed from AWS."
