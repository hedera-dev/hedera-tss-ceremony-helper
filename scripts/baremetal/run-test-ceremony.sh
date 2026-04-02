#!/bin/sh
set -eu

# Check the participant ID is set and within the valid range.
if [ -z "${PARTICIPANT_ID:-}" ]; then
  echo "Error: PARTICIPANT_ID environment variable is not set."
  echo "Example: export PARTICIPANT_ID=1000000001"
  exit 1
fi

if [ "$PARTICIPANT_ID" -lt 1000000001 ] || [ "$PARTICIPANT_ID" -gt 1000000020 ]; then
  echo "Error: PARTICIPANT_ID must be between 1000000001 and 1000000020 (got: $PARTICIPANT_ID)."
  exit 1
fi

# Check credentials are set.
if [ -z "$TSS_CEREMONY_S3_ACCESS_KEY" ] || [ -z "$TSS_CEREMONY_S3_SECRET_KEY" ]; then
  echo "Error: S3 credentials are not set."
  echo "Please export TSS_CEREMONY_S3_ACCESS_KEY and TSS_CEREMONY_S3_SECRET_KEY before running the ceremony."
  exit 1
fi

# Checks keys are present.
if [ ! -d "./keys" ] || [ -z "$(ls -A ./keys)" ]; then
  echo "Error: No keys found in ./keys directory."
  echo "Please place the participant's key and certificate files in the ./keys directory before running the ceremony."
  exit 1
fi

# Create logs and temp directories if they don't exist.
mkdir -p "$(pwd)/logs"
mkdir -p "$(pwd)/tmp"

# Ensure the podman machine is running and configured with all host CPUs and 16 GB of memory.
# To run the ceremony you need at least 16 GB of memory and 2 cpus (4 threads).
REQUIRED_CPUS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)
REQUIRED_MEMORY=16384

# On macOS, podman runs inside a VM (podman machine); on Linux, podman runs natively.
if [ "$(uname -s)" = "Darwin" ]; then
  CURRENT_CPUS=$(podman machine inspect --format '{{.Resources.CPUs}}' 2>/dev/null || echo 0)
  CURRENT_MEMORY=$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || echo 0)
  MACHINE_STATE=$(podman machine info --format '{{.Host.MachineState}}' 2>/dev/null || echo "Stopped")

  if [ "$MACHINE_STATE" != "Running" ]; then
    podman machine set --cpus="${REQUIRED_CPUS}" --memory="${REQUIRED_MEMORY}"
    podman machine start
  elif [ "$CURRENT_CPUS" -ne "$REQUIRED_CPUS" ] || [ "$CURRENT_MEMORY" -ne "$REQUIRED_MEMORY" ]; then
    echo "Podman machine is configured with ${CURRENT_CPUS} CPUs and ${CURRENT_MEMORY} MB of memory."
    echo "The ceremony requires ${REQUIRED_CPUS} CPUs and ${REQUIRED_MEMORY} MB of memory."
    printf "Stop, reconfigure and restart the podman machine? [y/N] "
    read -r REPLY
    case "${REPLY}" in
      [yY]|[yY][eE][sS])
        podman machine stop
        podman machine set --cpus="${REQUIRED_CPUS}" --memory="${REQUIRED_MEMORY}"
        podman machine start
        ;;
      *)
        echo "Continuing with current podman machine configuration."
        ;;
    esac
  fi

  # Ensure the podman machine is synchronized with the host's date and time.
  podman machine ssh sudo date --set "$(date +'%Y-%m-%dT%H:%M:%S')"
fi

CONTAINER_NAME="hedera-tss-ceremony"
# Remove any existing container with the same name from a previous run.
if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
  echo "Removing existing container '${CONTAINER_NAME}' from a previous run..."
  podman rm -f "${CONTAINER_NAME}" > /dev/null
fi

# Test ceremony parameters
PARTICIPANT_IDS="${PARTICIPANT_IDS:-1000000001,1000000002,1000000003,1000000004,1000000005,1000000006,1000000007,1000000008,1000000009,1000000010,1000000011,1000000012,1000000013,1000000014,1000000015,1000000016,1000000017,1000000018,1000000019,1000000020}"
JAR_URL="${JAR_URL:-https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar}"
JAR_HASH="${JAR_HASH:-786e87f95d4f1d84550e377c0e47930388a3d96afd8b5f56a544b2efee2a650a}"

echo "Running test ceremony with PARTICIPANT_ID=${PARTICIPANT_ID} and PARTICIPANT_IDS=${PARTICIPANT_IDS}"

# Run the container with the appropriate parameters for the test ceremony.
# The container runs without memory or cpu limits, and the same must be true for the podman machine.
podman run -d \
  --name "${CONTAINER_NAME}" \
  --cpus="${REQUIRED_CPUS}" \
  --memory=0 \
  -e TSS_CEREMONY_S3_ACCESS_KEY="$TSS_CEREMONY_S3_ACCESS_KEY" \
  -e TSS_CEREMONY_S3_SECRET_KEY="$TSS_CEREMONY_S3_SECRET_KEY" \
  -e JAR_URL="${JAR_URL}" \
  -e JAR_HASH="${JAR_HASH}" \
  -e RUST_BACKTRACE=full \
  -v "$(pwd)/logs:/app/logs" \
  -v "$(pwd)/keys:/app/keys:ro" \
  -v "$(pwd)/tmp:/tmp" \
  hedera-tss-ceremony-helper:latest \
  "${PARTICIPANT_ID}" \
  "${PARTICIPANT_IDS}" \
  us-east1 \
  https://storage.googleapis.com \
  tss-ceremony-mainnet \
  /app/keys/ \
  password

echo "Container ${CONTAINER_NAME} started. Following logs (CTRL+C to detach, container keeps running)..."
echo "To stop the ceremony: podman stop ${CONTAINER_NAME}"

# Follow the logs using podman logs instead of tailing the shared logs directory
podman logs -f "${CONTAINER_NAME}" | while IFS= read -r line; do printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"; done