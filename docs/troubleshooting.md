# Troubleshooting

## Container exits immediately after starting

Check the container logs for errors:

```sh
# Bare metal
podman logs hedera-tss-ceremony

# GCP
gcloud compute ssh "hedera-tss-ceremony-${PARTICIPANT_ID}" --zone="${GCP_ZONE}" -- \
  'docker logs hedera-tss-ceremony'
```

Common causes:

- **Missing or incorrect key files** — verify the files in `./keys/` use the correct `PARTICIPANT_ID+1` naming convention (e.g., `s-private-node1000000002.pem` for `PARTICIPANT_ID=1000000001`). See the [key file naming reference](#key-file-naming-reference) below.
- **Missing S3 credentials** — ensure `TSS_CEREMONY_S3_ACCESS_KEY` and `TSS_CEREMONY_S3_SECRET_KEY` are exported in your shell.
- **Wrong key file permissions** — key files should be readable by UID 1000 (the container user). On cloud deployments, the scripts set `chmod 600` automatically.

## JAR download fails at startup

The container downloads the ceremony JAR from a configurable URL (`JAR_URL`) on each fresh start. If this fails:

```
curl: (6) Could not resolve host: github.com
```

- Verify the machine has Internet access: `curl -I https://github.com`
- If behind a corporate proxy, configure the proxy in the container environment.
- If the download host is temporarily down, the container will use a cached JAR from a previous run if available.
- To use a different JAR URL, set `JAR_URL` before running the ceremony (see the main [README](../README.md#environment-variables)).

## Container cannot reach the S3 bucket

```
Unable to connect to endpoint https://storage.googleapis.com
```

- Verify outbound HTTPS (port 443) is allowed by your firewall or security group.
- Test connectivity: `curl -I https://storage.googleapis.com`
- Verify your S3 credentials are correct and have the necessary bucket permissions.

## Access denied (403) when writing to the bucket

```
S3ResponseException: Failed to upload text file
Response status code: 403
Details: ... does not have storage.objects.create access ...
```

This means your GCP account can **read** the bucket but cannot **write** to it. The Hedera team
needs to grant write permissions to your account on the ceremony bucket. Contact them with:

- Your GCP service account email or user email (shown in the error message)
- The bucket name (e.g. `tss-ceremony-mainnet`)

> **Note:** If the machine can read files (e.g. downloads parameters, finds `initial.ready`) but fails
> on write, this is a permissions issue — not a credential or connectivity problem. Your HMAC keys
> are correct; the bucket ACL just needs to be updated by the Hedera team.

## Clock drift (macOS / Podman)

Cryptographic protocols are sensitive to clock skew. On macOS, the Podman VM's clock can drift from the host.

The baremetal script syncs the clock automatically, but if you see timestamp-related errors:

```sh
podman machine ssh sudo date --set "$(date +'%Y-%m-%dT%H:%M:%S')"
```

## GCP startup script fails silently

The GCE startup script runs on every boot. If the container isn't running after a VM restart:

```sh
# SSH into the VM and check the startup script log
gcloud compute ssh "hedera-tss-ceremony-${PARTICIPANT_ID}" --zone="${GCP_ZONE}" -- \
  'sudo journalctl -u google-startup-scripts.service --no-pager -n 100'
```

## Cannot connect to Podman (macOS)

```
Cannot connect to Podman. Please verify your connection to the Linux system using
`podman system connection list`, or try `podman machine init` and `podman machine start`
```

On macOS, Podman runs inside a Linux VM. This VM can stop if your Mac sleeps, restarts, or
is idle for a long time. This is especially relevant during the 40-day ceremony window —
if your Mac sleeps, the Podman VM stops and so do your ceremony containers.

To recover:

```sh
podman machine start
```

Your containers will still exist but will be in a stopped state. Restart them:

```sh
podman start hedera-tss-ceremony
```

To prevent this from happening, disable sleep on your Mac while running the ceremony, or
run on a dedicated VM or cloud instance that won't sleep.

## Podman machine not starting (macOS)

If `podman machine start` fails:

```sh
# Check the machine status
podman machine info

# If corrupted, remove and reinitialise
podman machine rm
podman machine init
podman machine start
```

> **Warning:** removing the machine deletes the local image cache. You will need to rebuild the container image with `./scripts/build-oci-image.sh`.

## Key file naming reference

The ceremony software uses `PARTICIPANT_ID + 1` as the file index. If your files are named incorrectly, the container will fail at startup.

| `PARTICIPANT_ID` | Private key file | Public certificate file |
| --- | --- | --- |
| `1000000001` | `s-private-node1000000002.pem` | `s-public-node1000000002.pem` |
| `1000000003` | `s-private-node1000000004.pem` | `s-public-node1000000004.pem` |
| `1000000010` | `s-private-node1000000011.pem` | `s-public-node1000000011.pem` |
| `1000000020` | `s-private-node1000000021.pem` | `s-public-node1000000021.pem` |
