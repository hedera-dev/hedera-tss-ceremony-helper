# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera TSS Ceremony Helper — deployment and operations toolkit for running a TSS (Threshold Signature Scheme) cryptographic ceremony. Nodes coordinate via a GCP Cloud Storage bucket (S3-compatible API) in a turn-based protocol across a ~40-day window. This repo contains the container images, deployment scripts, and an S3 permission validation tool.

## Build Commands

```bash
# Install prerequisites (Podman)
./scripts/install-requirements.sh

# Build container image (default: JRE 25, multi-platform)
./scripts/build-oci-image.sh

# Build legacy variant (JDK 21)
VARIANT=legacy ./scripts/build-oci-image.sh

# Build single platform only
PLATFORMS=linux/amd64 ./scripts/build-oci-image.sh

# Build the S3 permission test JAR
cd ceremony-test-jar && ./gradlew build
```

## Run Test Ceremony

```bash
export NODE_ID="1000000001"
export TSS_CEREMONY_S3_ACCESS_KEY="<key>"
export TSS_CEREMONY_S3_SECRET_KEY="<secret>"
export VARIANT="default"
./scripts/baremetal/run-test-ceremony.sh
```

## Architecture

- **Java 21 application** (`ceremony-test-jar/`): Gradle project that builds a fat JAR validating S3 read/write permissions (28 operations) before the real ceremony. Main class: `com.hedera.ceremony.test.S3PermissionTest`.
- **Container images** (`oci/`): Two variants — `default` (JRE 25, lightweight) and `legacy` (JDK 21). Both use tini as PID 1 and run as non-root (UID 1000). The ceremony JAR is downloaded at container startup via `JAR_URL` env var.
- **Deployment scripts** (`scripts/`): Platform-specific automation for bare metal, GCP (Artifact Registry + Compute Engine), and AWS (EC2/Fargate). Each validates the environment before launching.
- **Key generation** (`scripts/key-and-certificate-generator.sh`): RSA 3072-bit keys + self-signed X.509 certs via OpenSSL. NODE_ID range: 1000000001–1000000020. Files use NODE_ID+1 naming (e.g., node `1000000001` → `s-private-node1000000002.pem`).

## Key Design Decisions

- **Podman over Docker** for rootless container operations
- **Fat JAR** with all dependencies embedded for simplified deployment
- **Environment-based configuration** — all credentials and settings via env vars, never in images
- **Shell scripts use `set -eu`** — fail on errors and undefined variables
- **No CI/CD** — this is an operations tool tested manually via deployment scripts
