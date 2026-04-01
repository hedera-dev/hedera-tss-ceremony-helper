# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hedera TSS Ceremony Helper — deployment and operations toolkit for running a TSS (Threshold Signature Scheme) cryptographic ceremony. Machines coordinate via a GCP Cloud Storage bucket (S3-compatible API) in a turn-based protocol across a ~40-day window. This repo contains the container images, deployment scripts, and an S3 permission validation tool.

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
export PARTICIPANT_ID="1000000001"
export TSS_CEREMONY_S3_ACCESS_KEY="<key>"
export TSS_CEREMONY_S3_SECRET_KEY="<secret>"
export VARIANT="default"
./scripts/baremetal/run-test-ceremony.sh
```

## Architecture

- **Java 21 application** (`ceremony-test-jar/`): Gradle project that builds a fat JAR validating S3 read/write permissions (28 operations) before the real ceremony. Main class: `com.hedera.ceremony.test.S3PermissionTest`.
- **Container images** (`oci/`): Two variants — `default` (JRE 25, lightweight) and `legacy` (JDK 21). Both use tini as PID 1 and run as non-root (UID 1000). The ceremony JAR is downloaded at container startup via `JAR_URL` env var.
- **Deployment scripts** (`scripts/`): Platform-specific automation for bare metal, GCP (Artifact Registry + Compute Engine), and AWS (EC2). Each validates the environment before launching.
- **Key generation** (`scripts/key-and-certificate-generator.sh`): RSA 3072-bit keys + self-signed X.509 certs via OpenSSL. PARTICIPANT_ID range: 1000000001–1000000020. Files use PARTICIPANT_ID+1 naming (e.g., participant ID `1000000001` → `s-private-node1000000002.pem`).

## Deployment Script Structure

Each cloud platform follows the same pattern:

| Script | Purpose |
| --- | --- |
| `scripts/<platform>/setup-participant.sh` | One-time setup: registry, secrets, IAM/SA, roles |
| `scripts/<platform>/create-test-instance.sh` | Launch a VM for the test ceremony |
| `scripts/<platform>/create-instance.sh` | Launch a VM for the real ceremony (AWS: stub) |
| `scripts/<platform>/clean-up-everything.sh` | Tear down VM + delete secrets after ceremony |

Startup/userdata scripts are templates (`*.sh.tpl`) with `<PLACEHOLDER>` variables substituted by `sed` in the create scripts before being passed to the cloud API. Do not execute `.tpl` files directly.

### AWS-specific

- `scripts/aws/ec2-userdata.sh.tpl`: rendered and passed via `--user-data` to `aws ec2 run-instances`. Contains a `<RESTART_POLICY>` placeholder — `create-test-instance.sh` sets it to `no` (run once); the production script should use `unless-stopped`.
- `aws ssm start-session` requires the **Session Manager plugin** (`brew install --cask session-manager-plugin` on macOS). All `docker` commands issued through SSM sessions must be prefixed with `sudo` (SSM runs as `ssm-user`, not root).
- Secrets Manager stores 4 secrets per participant: `tss-s3-access-key-<ID>`, `tss-s3-secret-key-<ID>`, `tss-participant-private-key-<ID>`, `tss-participant-public-cert-<ID>`.

### GCP-specific

- `scripts/gcp/gce-startup.sh.tpl`: runs on **every boot** of the GCE instance (via startup script metadata). Fetches secrets via the Secret Manager REST API directly (no `gcloud` on COS) using the instance metadata server for auth.
- GCP uses Container-Optimized OS; Docker is available but Podman is not.

## Key Design Decisions

- **Podman over Docker** for local/baremetal container operations; Docker is used on cloud VMs (Amazon Linux 2023, COS)
- **Fat JAR** with all dependencies embedded for simplified deployment
- **Environment-based configuration** — all credentials and settings via env vars, never in images
- **Shell scripts use `set -eu`** — fail on errors and undefined variables
- **No CI/CD** — this is an operations tool tested manually via deployment scripts
