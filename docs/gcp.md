# Run on GCP (Google Cloud Platform)

The recommended GCP approach is a **Compute Engine VM** running
[Container-Optimized OS (COS)](https://cloud.google.com/container-optimized-os/docs).
COS ships with Docker pre-installed and a service-account-aware credential helper,
so no manual Docker setup is needed. A startup script fetches secrets and key files
from Secret Manager and starts the ceremony container automatically on each boot.

## Machine type

| Bare-metal requirement | GCE equivalent |
| --- | --- |
| 2 cores / 4 threads | `e2-standard-4` (4 vCPUs, 16 GB RAM) |
| 16 GB RAM | Included in `e2-standard-4` |
| 60 GB SSD | 60 GB SSD persistent disk (boot disk) |
| 1 Gbps network | Standard for all GCE VMs |

## Prerequisites

- The [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) installed
  and authenticated (`gcloud auth login`).
- A GCP project with billing enabled.
- Your participant key and certificate in `./keys/` (see [Private key and certificate](../README.md#private-key-and-certificate)).
- Completed the [setup steps](../README.md#setup) in the main README (Podman installed, image built, credentials configured).

Set the following environment parameters in addition to those defined in the [environment variables](../README.md#environment-variables) section:

```sh
export GCP_PROJECT_ID="<your-project-id>"
export GCP_REGION="<your-region>"             # e.g. us-central1
export GCP_ZONE="<your-zone>"                 # e.g. us-central1-a
```

The script enables required APIs, creates the Artifact Registry repository, builds
and pushes the container image, stores your credentials and participant keys in Secret Manager and creates and configures a dedicated service account — all in a single step:

```sh
./scripts/gcp/setup-participant.sh
```

## Create the GCE instance

The startup script template is at `scripts/gcp/gce-startup.sh.tpl`. The wrapper scripts
below render the template with all ceremony parameters already set and create the VM in a
single command — no manual editing required.

### Production run

> **Note:** `scripts/gcp/create-instance.sh` is currently a stub — production parameters are still to be defined. For now, use the test instance script described below.

```sh
./scripts/gcp/create-instance.sh
```

### Test run

```sh
./scripts/gcp/create-test-instance.sh
```

> **Note:** the command above may print a warning like:
> `Disk size: '60 GB' is larger than image size: '10 GB'. You might need to resize the root partition manually...`
>
> This is a false alarm. COS automatically expands its stateful partition (`/var`) to fill the remaining disk on first boot — no manual intervention needed. The extra space is used by Docker and the ceremony logs.

## Logs

To view recent container output directly:

```sh
gcloud compute ssh "hedera-tss-ceremony-${PARTICIPANT_ID}" --zone="${GCP_ZONE}" -- \
  'docker logs -t hedera-tss-ceremony'
```

Logs are also written to `/var/tss/logs/` on the VM. To follow the latest log
file over SSH:

```sh
gcloud compute ssh "hedera-tss-ceremony-${PARTICIPANT_ID}" --zone="${GCP_ZONE}" -- \
  'tail -n +1 -f /var/tss/logs/$(ls -t /var/tss/logs/ | head -1)'
```

To view logs from inside the VM, you can run:

```shell
docker logs -t hedera-tss-ceremony
```

## Stopping the ceremony

To stop the container without deleting the VM:

```sh
gcloud compute ssh "hedera-tss-ceremony-${PARTICIPANT_ID}" --zone="${GCP_ZONE}" -- \
  'docker stop hedera-tss-ceremony'
```

To delete the VM entirely:

> **Warning:** this permanently deletes the VM and all data on its boot disk.
> Ensure all logs have been saved before proceeding.

```sh
gcloud compute instances delete "hedera-tss-ceremony-${PARTICIPANT_ID}" --zone="${GCP_ZONE}"
```

## Cleaning up after the ceremony

Once the ceremony is complete, delete the GCE instance and all secrets from
Secret Manager:

```sh
./scripts/gcp/clean-up-everything.sh
```

If the GCE instance still exists, the script deletes it (and its boot disk).
It then deletes all ceremony secrets from Secret Manager. The script asks for
confirmation before proceeding.
