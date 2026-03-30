# Run on AWS (Amazon Web Services)

**UNDER REVIEW** — the AWS deployment path (both EC2 and ECS Fargate) is a draft and may be
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
- Your node key and certificate in `./keys/` (see [Private key and certificate](../README.md#private-key-and-certificate)).
- Completed the [setup steps](../README.md#setup) in the main README (Podman installed, image built, credentials configured).

Set the following environment parameters in addition to those defined in the [environment variables](../README.md#environment-variables) section:

```sh
export AWS_REGION="<your-region>"             # e.g. us-east-1
```

Then run the setup script once. It creates the ECR repository, builds and pushes the
container image, stores your credentials and node keys in Secrets Manager, creates the
IAM role with least-privilege access, and configures both the EC2 instance profile and
the ECS Fargate roles — all in a single step:

```sh
./scripts/aws/setup-node.sh
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
stream per node. To query them from the command line:

```sh
aws logs get-log-events \
  --region "${AWS_REGION}" \
  --log-group-name /hedera-tss-ceremony \
  --log-stream-name "node-${NODE_ID}" \
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

## Run on ECS Fargate

[ECS Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
is a serverless container service with no execution time limit, making it well
suited for the ~40-day ceremony window. There is no VM to manage: AWS runs the
task on managed infrastructure, restarts it on failure via the ECS service
desired-count mechanism, and forwards logs to CloudWatch Logs automatically.

S3 credentials are injected as environment variables directly by ECS from
Secrets Manager — no AWS CLI calls at runtime for those. Node key files are
fetched from Secrets Manager by a lightweight init container at task startup
and written to a shared ephemeral volume mounted into the main container.

### Prerequisites

- The [AWS CLI (`aws`)](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
  installed and configured (`aws configure`).
- An AWS account with permissions to manage EC2, ECR, Secrets Manager, and IAM.
- Your node key and certificate in `./keys/` (see [Private key and certificate](../README.md#private-key-and-certificate)).

Set the following environment parameters in addition to those defined in the [environment variables](../README.md#environment-variables) section:

```sh
export AWS_REGION="<your-region>"             # e.g. us-east-1
```

The ECR repository, image, Secrets Manager secrets, and IAM roles are shared
with the EC2 path. If you have not done so already, complete the AWS setup step:

```sh
./scripts/aws/setup-node.sh
```

> If you already ran `./scripts/aws/setup-node.sh` for the EC2 path, you can skip
> this — all required resources are already in place.

### Run the ceremony

The task definition template is at `scripts/aws/ecs-task-definition.json.tpl`.
The wrapper scripts below render the template, register the task definition,
create an ECS cluster (if needed), and deploy a Fargate service with
`desiredCount=1` — so ECS automatically restarts the task if it exits
unexpectedly.

#### Production run

> **Note:** `scripts/aws/run-fargate-task.sh` is currently a stub — production
> parameters are still to be defined. For now, use the test task script
> described below.

```sh
./scripts/aws/run-fargate-task.sh
```

#### Test run

```sh
./scripts/aws/run-test-fargate-task.sh
```

### Logs

Container logs are forwarded automatically to **CloudWatch Logs** via the
`awslogs` log driver, under the log group `/hedera-tss-ceremony`. Each node
has its own stream prefixed with `node-<NODE_ID>`. To query them:

```sh
aws logs get-log-events \
  --region "${AWS_REGION}" \
  --log-group-name /hedera-tss-ceremony \
  --log-stream-name "node-${NODE_ID}/hedera-tss-ceremony/<TASK_ID>" \
  --output text
```

Or browse them in the [CloudWatch console](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups).

### Stopping the ceremony

To stop the task without deleting the service (ECS will restart it per
`desiredCount=1`):

```sh
TASK_ARN=$(aws ecs list-tasks \
  --region "${AWS_REGION}" \
  --cluster hedera-tss \
  --service-name "hedera-tss-ceremony-${NODE_ID}" \
  --query 'taskArns[0]' --output text)

aws ecs stop-task \
  --region "${AWS_REGION}" \
  --cluster hedera-tss \
  --task "${TASK_ARN}"
```

To stop permanently, scale the service to zero first, then delete it:

```sh
aws ecs update-service \
  --region "${AWS_REGION}" \
  --cluster hedera-tss \
  --service "hedera-tss-ceremony-${NODE_ID}" \
  --desired-count 0

aws ecs delete-service \
  --region "${AWS_REGION}" \
  --cluster hedera-tss \
  --service "hedera-tss-ceremony-${NODE_ID}"
```
