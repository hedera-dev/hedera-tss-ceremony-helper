#!/usr/bin/env sh
# setup.sh — One-time AWS resource setup for the Hedera TSS Ceremony Helper.
#
# Run this script once before creating the EC2 instance or ECS Fargate service.
# It is idempotent and safe to run again if any step was previously completed.
# This script covers both the EC2 and ECS Fargate deployment paths.
#
# Required environment variables (set once in your shell profile):
#   AWS_REGION                 AWS region (e.g. us-east-1)
#   NODE_ID                    Your node ID (e.g. 1000000001)
#   TSS_CEREMONY_S3_ACCESS_KEY GCP S3 access key for the ceremony bucket
#   TSS_CEREMONY_S3_SECRET_KEY GCP S3 secret key for the ceremony bucket
#
# Requirements: AWS CLI authenticated via `aws configure` or environment variables.
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

# ── Environment ───────────────────────────────────────────────────────────────
: "${AWS_REGION:?AWS_REGION is required}"
: "${NODE_ID:?NODE_ID is required}"
: "${TSS_CEREMONY_S3_ACCESS_KEY:?TSS_CEREMONY_S3_ACCESS_KEY is required}"
: "${TSS_CEREMONY_S3_SECRET_KEY:?TSS_CEREMONY_S3_SECRET_KEY is required}"

NODE_ID_PLUS_1=$((NODE_ID + 1))
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ── Create ECR repository ─────────────────────────────────────────────────────
echo "==> Creating ECR repository..."
aws ecr create-repository \
  --region "${AWS_REGION}" \
  --repository-name hedera-tss/hedera-tss-ceremony-helper \
  --output text > /dev/null 2>&1 \
  || echo "   (ECR repository already exists — skipping)"

# ── Build the container image ─────────────────────────────────────────────────
echo "==> Building container image..."
"${REPO_ROOT}/scripts/build-oci-image.sh"

# ── Push the image to ECR ─────────────────────────────────────────────────────
echo "==> Authenticating Podman to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  podman login --username AWS --password-stdin \
  "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hedera-tss/hedera-tss-ceremony-helper:latest"
echo "==> Pushing image to ${IMAGE}..."
podman manifest push hedera-tss-ceremony-helper:latest "${IMAGE}"

# ── Store S3 credentials in Secrets Manager ───────────────────────────────────
echo "==> Storing S3 credentials in Secrets Manager..."
aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "tss-s3-access-key-${NODE_ID}" \
  --secret-string "${TSS_CEREMONY_S3_ACCESS_KEY}" \
  --output text > /dev/null 2>&1 \
  || aws secretsmanager put-secret-value \
       --region "${AWS_REGION}" \
       --secret-id "tss-s3-access-key-${NODE_ID}" \
       --secret-string "${TSS_CEREMONY_S3_ACCESS_KEY}" \
       --output text > /dev/null

aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "tss-s3-secret-key-${NODE_ID}" \
  --secret-string "${TSS_CEREMONY_S3_SECRET_KEY}" \
  --output text > /dev/null 2>&1 \
  || aws secretsmanager put-secret-value \
       --region "${AWS_REGION}" \
       --secret-id "tss-s3-secret-key-${NODE_ID}" \
       --secret-string "${TSS_CEREMONY_S3_SECRET_KEY}" \
       --output text > /dev/null

# ── Store node key and certificate in Secrets Manager ────────────────────────
echo "==> Storing node key and certificate in Secrets Manager..."
aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "tss-node-private-key-${NODE_ID}" \
  --secret-string "file://./keys/s-private-node${NODE_ID_PLUS_1}.pem" \
  --output text > /dev/null 2>&1 \
  || aws secretsmanager put-secret-value \
       --region "${AWS_REGION}" \
       --secret-id "tss-node-private-key-${NODE_ID}" \
       --secret-string "file://./keys/s-private-node${NODE_ID_PLUS_1}.pem" \
       --output text > /dev/null

aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "tss-node-public-cert-${NODE_ID}" \
  --secret-string "file://./keys/s-public-node${NODE_ID_PLUS_1}.pem" \
  --output text > /dev/null 2>&1 \
  || aws secretsmanager put-secret-value \
       --region "${AWS_REGION}" \
       --secret-id "tss-node-public-cert-${NODE_ID}" \
       --secret-string "file://./keys/s-public-node${NODE_ID_PLUS_1}.pem" \
       --output text > /dev/null

# ── Create IAM role and instance profile for EC2 ─────────────────────────────
echo "==> Creating EC2 IAM role and instance profile..."
aws iam create-role \
  --role-name hedera-tss-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  --output text > /dev/null 2>&1 \
  || echo "   (EC2 role already exists — skipping)"

aws iam put-role-policy \
  --role-name hedera-tss-role \
  --policy-name tss-secrets-access \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":[\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-s3-access-key-*\",\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-s3-secret-key-*\",\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-node-private-key-*\",\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-node-public-cert-*\"]}]}"

aws iam attach-role-policy \
  --role-name hedera-tss-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name hedera-tss-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

aws iam attach-role-policy \
  --role-name hedera-tss-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
  --instance-profile-name hedera-tss-instance-profile \
  --output text > /dev/null 2>&1 \
  || echo "   (instance profile already exists — skipping)"

aws iam add-role-to-instance-profile \
  --instance-profile-name hedera-tss-instance-profile \
  --role-name hedera-tss-role 2>/dev/null \
  || echo "   (role already attached to instance profile — skipping)"

# ── Create IAM roles for ECS Fargate ─────────────────────────────────────────
echo "==> Creating ECS Fargate IAM roles..."

# Task execution role
aws iam create-role \
  --role-name hedera-tss-ecs-execution-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  --output text > /dev/null 2>&1 \
  || echo "   (ECS execution role already exists — skipping)"

aws iam attach-role-policy \
  --role-name hedera-tss-ecs-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam put-role-policy \
  --role-name hedera-tss-ecs-execution-role \
  --policy-name tss-s3-secrets-access \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":[\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-s3-access-key-*\",\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-s3-secret-key-*\"]}]}"

# Task role
aws iam create-role \
  --role-name hedera-tss-ecs-task-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  --output text > /dev/null 2>&1 \
  || echo "   (ECS task role already exists — skipping)"

aws iam put-role-policy \
  --role-name hedera-tss-ecs-task-role \
  --policy-name tss-key-secrets-access \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":[\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-node-private-key*\",\"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:tss-node-public-cert*\"]}]}"

echo ""
echo "==> AWS setup complete. You can now run the ceremony:"
echo ""
echo "    EC2:         ./scripts/aws/create-test-instance.sh"
echo "    ECS Fargate: ./scripts/aws/run-test-fargate-task.sh"
echo ""
