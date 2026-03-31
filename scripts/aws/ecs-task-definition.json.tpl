{
  "family": "hedera-tss-ceremony-<PARTICIPANT_ID>",
  "comment": "DO NOT use directly. Rendered by run-test-fargate-task.sh / run-fargate-task.sh.",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "4096",
  "memory": "16384",
  "executionRoleArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/hedera-tss-ecs-execution-role",
  "taskRoleArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/hedera-tss-ecs-task-role",
  "volumes": [
    { "name": "keys" }
  ],
  "containerDefinitions": [
    {
      "name": "keys-init",
      "image": "public.ecr.aws/aws-cli/aws-cli:latest",
      "essential": false,
      "entryPoint": ["sh", "-c"],
      "command": [
        "aws secretsmanager get-secret-value --region <AWS_REGION> --secret-id tss-participant-private-key-<PARTICIPANT_ID> --query SecretString --output text > /keys/s-private-node<PARTICIPANT_ID_PLUS_1>.pem && aws secretsmanager get-secret-value --region <AWS_REGION> --secret-id tss-participant-public-cert-<PARTICIPANT_ID> --query SecretString --output text > /keys/s-public-node<PARTICIPANT_ID_PLUS_1>.pem && chmod 600 /keys/*.pem"
      ],
      "mountPoints": [
        { "sourceVolume": "keys", "containerPath": "/keys" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "<AWS_REGION>",
          "awslogs-group": "/hedera-tss-ceremony",
          "awslogs-stream-prefix": "keys-init",
          "awslogs-create-group": "true"
        }
      }
    },
    {
      "name": "hedera-tss-ceremony",
      "image": "<IMAGE>",
      "essential": true,
      "dependsOn": [
        { "containerName": "keys-init", "condition": "COMPLETE" }
      ],
      "command": [
        "<PARTICIPANT_ID>",
        "<PARTICIPANT_IDS>",
        "<S3_REGION>",
        "<S3_ENDPOINT>",
        "<S3_BUCKET>",
        "/app/keys/",
        "password"
      ],
      "environment": [
        {
          "name": "JAR_URL",
          "value": "<JAR_URL>"
        },
        {
          "name": "RUST_BACKTRACE",
          "value": "full"
        }
      ],
      "secrets": [
        {
          "name": "TSS_CEREMONY_S3_ACCESS_KEY",
          "valueFrom": "arn:aws:secretsmanager:<AWS_REGION>:<AWS_ACCOUNT_ID>:secret:tss-s3-access-key-<PARTICIPANT_ID>"
        },
        {
          "name": "TSS_CEREMONY_S3_SECRET_KEY",
          "valueFrom": "arn:aws:secretsmanager:<AWS_REGION>:<AWS_ACCOUNT_ID>:secret:tss-s3-secret-key-<PARTICIPANT_ID>"
        }
      ],
      "mountPoints": [
        { "sourceVolume": "keys", "containerPath": "/app/keys", "readOnly": true }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "<AWS_REGION>",
          "awslogs-group": "/hedera-tss-ceremony",
          "awslogs-stream-prefix": "participant-<PARTICIPANT_ID>",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
