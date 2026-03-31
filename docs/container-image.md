# Container image details

The scripts running the ceremony use a container with the correct preconfigured parameters. **You should not change those parameters**, unless instructed by the Hedera team accordingly and you understand the implications. All parameters are set internally by the scripts based on your environment variables.

## Container parameters

| Position | Value | Description |
| --- | --- | --- |
| 1 | `PARTICIPANT_ID` | This participant's ID (integer, from `1000000001` to `1000000020`) — set via the `PARTICIPANT_ID` environment variable |
| 2 | `PARTICIPANT_IDS` | Comma-separated list of **all** participating participant IDs (no spaces; order must be identical on all participants) |
| 3 | `REGION` | S3 bucket region (e.g. `us-east1`) |
| 4 | `ENDPOINT` | S3 endpoint URL (e.g. `https://storage.googleapis.com`) |
| 5 | `BUCKET` | S3 bucket name |
| 6 | `KEYS_PATH` | Path to participant keys inside the container (default: `/app/keys/`) |
| 7 | `PASSWORD` | Key-loader password — use the literal string `password` |

## Ceremony JAR URL (`JAR_URL`) and hash verification (`JAR_HASH`)

The container entrypoint downloads the ceremony JAR from a configurable URL at startup. The `JAR_URL` environment variable controls which JAR is downloaded:

- **Default:** A test JAR from GitHub Releases that validates S3 read/write permissions.
- **Override:** Set `JAR_URL` to point to a different JAR (e.g. the real `hedera-cryptography-ceremony` when it becomes available).

The `JAR_HASH` environment variable is **required** and must contain the expected SHA-256 hash of the JAR. After downloading, the entrypoint computes the SHA-256 hash of the file and compares it against `JAR_HASH`. If they do not match, the container stops immediately with an error. This prevents executing a tampered or corrupted JAR.

The JAR is downloaded on every container start. When `JAR_URL` changes, update `JAR_HASH` accordingly and restart the container.

## JDK 21 OCI image

The repository contains an additional OCI image using JDK 21. In case the Hedera team ask for it, you can build it using the provided script.

```sh
VARIANT=legacy ./scripts/build-oci-image.sh
```

The image will override the `hedera-tss-ceremony-helper:latest` tag in your local Podman image store, so when you restart the ceremony it will use the new image with JDK 21 instead of the default one with JRE 25.
