#!/usr/bin/env sh
# build-oci-image.sh — builds the OCI image for hedera-tss-ceremony-helper using Podman.
#
# Usage:
#   ./scripts/build-oci-image.sh [TAG]
#
# Environment variables:
#   TAG       Image tag (default: latest)
#   VARIANT   Image variant: 'default' (eclipse-temurin 25 JRE, default) or
#             'legacy' (eclipse-temurin 21 JDK)
#   PLATFORMS Comma-separated list of platforms (default: linux/amd64,linux/arm64)
#
# Examples:
#   ./scripts/build-oci-image.sh                           # default variant, tag 'latest'
#   ./scripts/build-oci-image.sh 1.2.3                     # default variant, tag '1.2.3'
#   VARIANT=legacy ./scripts/build-oci-image.sh            # legacy (JDK 21) variant
#   VARIANT=legacy ./scripts/build-oci-image.sh 1.2.3      # legacy variant, tag '1.2.3'
#   PLATFORMS=linux/amd64 ./scripts/build-oci-image.sh     # single platform
#
# Requirements: run ./scripts/install-requirements.sh if podman is not installed.
#
set -eu

IMAGE_NAME="hedera-tss-ceremony-helper"
TAG="${1:-${TAG:-latest}}"
VARIANT="${VARIANT:-default}"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Validate variant.
case "${VARIANT}" in
  default|legacy) ;;
  *) echo "ERROR: unknown VARIANT '${VARIANT}'. Use 'default' or 'legacy'." >&2; exit 1 ;;
esac

# Resolve the project root (one level above this script's directory).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OCI_DIR="${PROJECT_ROOT}/oci/${VARIANT}"

if ! command -v podman > /dev/null 2>&1; then
  echo "ERROR: podman not found in PATH." >&2
  echo "Run ./scripts/install-requirements.sh to install it." >&2
  exit 1
fi

# On macOS, Podman requires a running VM. Start it if it is not already running.
if [ "$(uname -s)" = "Darwin" ]; then
  if ! podman machine inspect 2>/dev/null | grep -q '"State": "running"'; then
    echo "Podman machine is not running — starting it..."
    podman machine start
  fi
fi

echo "Building image: ${FULL_IMAGE}"
echo "Variant:        ${VARIANT}"
echo "Context:        ${OCI_DIR}"
echo "Containerfile:  ${OCI_DIR}/Containerfile"
echo "Platforms:      ${PLATFORMS}"
echo ""

# Remove any existing manifest list so we start fresh.
podman manifest rm "${FULL_IMAGE}" 2>/dev/null || true

# Build each platform and collect it into a local manifest list.
OLD_IFS="${IFS}"; IFS=","
for P in ${PLATFORMS}; do
  IFS="${OLD_IFS}"
  echo "-- building ${P} --"
  podman build \
    --no-cache \
    --file     "${OCI_DIR}/Containerfile" \
    --platform "${P}" \
    --manifest "${FULL_IMAGE}" \
    "${OCI_DIR}"
done
IFS="${OLD_IFS}"

echo ""
echo "Successfully built ${FULL_IMAGE}"
echo "Inspect with: podman manifest inspect ${FULL_IMAGE}"
