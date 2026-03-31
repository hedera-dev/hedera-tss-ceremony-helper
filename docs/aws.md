# Run on AWS (Amazon Web Services)

**UNDER REVIEW** — the AWS EC2 deployment path is a draft and may be
subject to changes. Please refer to the bare metal or the GCP guides if you want to follow a verified installation process.

## Run on EC2

The recommended AWS approach is an **EC2 instance** running Amazon Linux 2023.
Amazon Linux 2023 integrates natively with IAM roles and AWS CLI, so no manual
credential management is needed on the instance. A user data script fetches
secrets and key files from Secrets Manager and starts the ceremony container
automatically on first boot.

### Machine type

| Bare-metal requirement | EC2 equivalent |
| --- | --- |
| 2 cores / 4 threads | `m6i.xlarge` (4 vCPUs, 16 GB RAM) |
| 16 GB RAM | Included in `m6i.xlarge` |
| 60 GB SSD | 60 GB gp3 EBS root volume |
| 1 Gbps network | Standard for all EC2 instances |

### Prerequisites

- The [AWS CLI (`aws`)](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
  installed and configured (`aws configure`).
- An AWS account with permissions to manage EC2, ECR, Secrets Manager, and IAM.
- Your participant key and certificate in `./keys/` (see [Private key and certificate](../README.md#private-key-and-certificate)).
- Completed the [setup steps](../README.md#setup) in the main README (Podman installed, image built, credentials configured).

Set the following environment parameters in addition to those defined in the [environment variables](../README.md#environment-variables) section:

```sh
export AWS_REGION="<your-region>"             # e.g. us-east-1
```

Then run the setup script once. It creates the ECR repository, builds and pushes the
container image, stores your credentials and participant keys in Secrets Manager, and creates the
IAM role with least-privilege access and the EC2 instance profile — all in a single step:

```sh
./scripts/aws/setup-participant.sh
```

### Create the EC2 instance

The user data template is at `scripts/aws/ec2-userdata.sh.tpl`. The wrapper scripts below
render the template with all ceremony parameters already set and create the instance in a
single command — no manual editing required.

#### Production run

> **Note:** `scripts/aws/create-instance.sh` is currently a stub — production parameters are still to be defined. For now, use the test instance script described below.

```sh
./scripts/aws/create-instance.sh
```

#### Test run

```sh
./scripts/aws/create-test-instance.sh
```

### Logs

Container logs are forwarded automatically to **CloudWatch Logs** via the
`awslogs` Docker driver, under the log group `/hedera-tss-ceremony` with one
stream per participant. To query them from the command line:

```sh
aws logs get-log-events \
  --region "${AWS_REGION}" \
  --log-group-name /hedera-tss-ceremony \
  --log-stream-name "participant-${PARTICIPANT_ID}" \
  --output text
```

Or browse them in the [CloudWatch console](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups).

Logs are also written to `/var/tss/logs/` on the instance. To follow the latest
log file via SSM Session Manager (no inbound ports required):

```sh
aws ssm start-session \
  --region "${AWS_REGION}" \
  --target <INSTANCE_ID> \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["tail -n +1 -f /var/tss/logs/$(ls -t /var/tss/logs/ | head -1)"]'
```

### Stopping the ceremony

To stop the container without terminating the instance:

```sh
aws ssm start-session \
  --region "${AWS_REGION}" \
  --target <INSTANCE_ID> \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["docker stop hedera-tss-ceremony"]'
```

To terminate the instance entirely:

> **Warning:** this permanently destroys the instance and its root volume.
> Ensure all logs have been saved before proceeding.

```sh
aws ec2 terminate-instances \
  --region "${AWS_REGION}" \
  --instance-ids <INSTANCE_ID>
```
