#!/usr/bin/env sh
# entrypoint.sh — downloads the latest hedera-cryptography-ceremony JAR and runs it.
set -eu

JAR="hedera-cryptography-ceremony.jar"
JAR_URL="${JAR_URL:=https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases/download/test-jar/ceremony-s3-permission-test.jar}"

echo "Downloading ${JAR_URL} ..."
curl -fsSL "${JAR_URL}" -o "${JAR}"

# Generate a unique log filename using UTC date and nanoseconds.
RUN_ID="$(TZ=Etc/UTC date -u +%Y%m%dT%H%M%S)"
LOG_FILE="/app/logs/tss-ceremony.${RUN_ID}.log"
mkdir -p /app/logs

# Print the Java version for debugging purposes.
echo "Using the following Java version:"
java -version

echo "Starting hedera-cryptography-ceremony (log: ${LOG_FILE})..."
# TSS_CEREMONY_S3_ACCESS_KEY and TSS_CEREMONY_S3_SECRET_KEY are expected to be
# set in the container environment (e.g. via -e flags on podman/docker run).
# tini is PID 1 and handles signal forwarding, so exec is not needed here.
java -jar "${JAR}" "$@" 2>&1 | tee "${LOG_FILE}"