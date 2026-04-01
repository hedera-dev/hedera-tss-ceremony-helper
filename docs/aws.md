# Run on AWS EC2 (Amazon Web Services)

The recommended AWS approach is an **EC2 instance** running Amazon Linux 2023.
Amazon Linux 2023 integrates natively with IAM roles and AWS CLI, so no manual
credential management is needed on the instance. A user data script fetches
secrets and key files from Secrets Manager and starts the ceremony container
automatically on first boot.

## Machine type

| Bare-metal requirement | EC2 equivalent |
| --- | --- |
| 2 cores / 4 threads | `m6i.xlarge` (4 vCPUs, 16 GB RAM) |
| 16 GB RAM | Included in `m6i.xlarge` |
| 60 GB SSD | 60 GB gp3 EBS root volume |
| 1 Gbps network | Standard for all EC2 instances |

## Prerequisites

- The [AWS CLI (`aws`)](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
  installed and configured (`aws configure`).
- The [AWS Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  installed (required for `aws ssm start-session`).

  On macOS (recommended):

  ```sh
  brew install --cask session-manager-plugin
  ```

  On macOS (manual) or Linux, download the package from the
  [AWS documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  and install it. On macOS the `.pkg` installer does not create a symlink, so add one manually:

  ```sh
  sudo ln -s /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin
  ```

- An IAM user or role with the permissions listed below.
- Your participant key and certificate in `./keys/` (see [Private key and certificate](../README.md#private-key-and-certificate)).
- Completed the [setup steps](../README.md#setup) in the main README (Podman installed, image built, credentials configured).

### Required IAM permissions for the operator

Attach the following inline policy to the IAM user (or role) that runs `setup-participant.sh` and
the `create-*-instance.sh` scripts. Replace `<AWS_ACCOUNT_ID>` with your account ID (e.g. `008049031881`).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:CreateRepository",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:*:<AWS_ACCOUNT_ID>:repository/hedera-tss/*"
    },
    {
      "Sid": "SecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:DeleteSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:<AWS_ACCOUNT_ID>:secret:tss-*"
    },
    {
      "Sid": "IAMSetup",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:GetRole",
        "iam:GetInstanceProfile",
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::<AWS_ACCOUNT_ID>:role/hedera-tss-role",
        "arn:aws:iam::<AWS_ACCOUNT_ID>:instance-profile/hedera-tss-instance-profile"
      ]
    },
    {
      "Sid": "EC2Launch",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:DescribeImages",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMSession",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession"
      ],
      "Resource": [
        "arn:aws:ec2:*:<AWS_ACCOUNT_ID>:instance/*",
        "arn:aws:ssm:*::document/AWS-StartInteractiveCommand",
        "arn:aws:ssm:*:<AWS_ACCOUNT_ID>:session/*"
      ]
    },
    {
      "Sid": "CloudWatchLogsRead",
      "Effect": "Allow",
      "Action": [
        "logs:GetLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups"
      ],
      "Resource": "arn:aws:logs:*:<AWS_ACCOUNT_ID>:log-group:/hedera-tss-ceremony:*"
    }
  ]
}
```

> **Note:** `ecr:GetAuthorizationToken` must have `Resource: "*"` — it is not a per-repository
> action and cannot be scoped further.

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

## Create the EC2 instance

The user data template is at `scripts/aws/ec2-userdata.sh.tpl`. The wrapper scripts below
render the template with all ceremony parameters already set and create the instance in a
single command — no manual editing required.

### Production run

> **Note:** `scripts/aws/create-instance.sh` is currently a stub — production parameters are still to be defined. For now, use the test instance script described below.

```sh
./scripts/aws/create-instance.sh
```

### Test run

```sh
./scripts/aws/create-test-instance.sh
```

The script prints the instance ID on completion. Export it for use in subsequent commands:

```sh
export INSTANCE_ID="<id printed by the script above>"
```

## Logs

Container logs are forwarded automatically to **CloudWatch Logs** via the
`awslogs` Docker driver, under the log group `/hedera-tss-ceremony` with one
stream per participant. To query them from the command line:

```sh
aws logs get-log-events \
  --region "${AWS_REGION}" \
  --log-group-name /hedera-tss-ceremony \
  --log-stream-name "participant-${PARTICIPANT_ID}" \
  --no-cli-pager
```

Or browse them in the [CloudWatch console](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups).

To follow the container logs via SSM Session Manager (no inbound ports required):

```sh
aws ssm start-session \
  --region "${AWS_REGION}" \
  --target ${INSTANCE_ID} \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["sudo docker logs -f hedera-tss-ceremony"]'
```

## Stopping the ceremony

To stop the container without terminating the instance:

```sh
aws ssm start-session \
  --region "${AWS_REGION}" \
  --target ${INSTANCE_ID} \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["sudo docker stop hedera-tss-ceremony"]'
```

To terminate the instance entirely:

> **Warning:** this permanently destroys the instance and its root volume.
> Ensure all logs have been saved before proceeding.

```sh
aws ec2 terminate-instances \
  --region "${AWS_REGION}" \
  --instance-ids ${INSTANCE_ID}
  --no-cli-pager
```

## Cleaning up after the ceremony

Once the ceremony is complete, terminate the EC2 instance and delete all secrets
from Secrets Manager:

```sh
export INSTANCE_ID="<your-instance-id>"   # optional — omit to only delete secrets
./scripts/aws/clean-up-everything.sh
```

If `INSTANCE_ID` is set, the script terminates the EC2 instance (and its root
volume). It then deletes all ceremony secrets from Secrets Manager. The script
asks for confirmation before proceeding.
