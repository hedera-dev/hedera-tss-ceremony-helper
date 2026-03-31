#!/bin/sh
# clean-up-everything.sh — Cleans up after the ceremony on a bare metal / VM setup.
#
# This script:
#   1. Stops and removes the ceremony container.
#   2. Deletes participant key and certificate files from ./keys/.
#
# Usage:
#   ./scripts/baremetal/clean-up-everything.sh
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEYS_DIR="${REPO_ROOT}/keys"
CONTAINER_NAME="hedera-tss-ceremony"

HAS_CONTAINER=false
if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  HAS_CONTAINER=true
fi

HAS_KEYS=false
if [ -d "${KEYS_DIR}" ] && [ -n "$(ls -A "${KEYS_DIR}" 2>/dev/null)" ]; then
  HAS_KEYS=true
fi

if [ "${HAS_CONTAINER}" = false ] && [ "${HAS_KEYS}" = false ]; then
  echo "Nothing to clean up — no container and no key files found."
  exit 0
fi

echo "This will permanently:"
echo ""
if [ "${HAS_CONTAINER}" = true ]; then
  echo "  - Stop and remove the container '${CONTAINER_NAME}'"
fi
if [ "${HAS_KEYS}" = true ]; then
  echo "  - Delete the following key files:"
  for f in "${KEYS_DIR}"/*; do
    echo "      $(basename "${f}")"
  done
fi
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

# ── Stop and remove the container ────────────────────────────────────────────
if [ "${HAS_CONTAINER}" = true ]; then
  echo "==> Stopping and removing container '${CONTAINER_NAME}'..."
  podman rm -f "${CONTAINER_NAME}" > /dev/null
  echo "   Container removed."
fi

# ── Delete key files ─────────────────────────────────────────────────────────
if [ "${HAS_KEYS}" = true ]; then
  echo "==> Deleting key files from ${KEYS_DIR}..."
  rm -f "${KEYS_DIR}"/*.pem
  echo "   Key files deleted."
fi

echo ""
echo "Done."
