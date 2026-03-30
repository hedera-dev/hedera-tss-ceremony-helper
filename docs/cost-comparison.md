# Cost comparison for cloud services

**UNDER REVIEW** — AWS pricing and deployment paths may change.

All estimates assume a **40-day ceremony window** (960 hours) with resources
running continuously. Prices are on-demand rates in `us-east-1` / `us-central1`
as of early 2026 — check the official pricing pages for the most current figures.

| | GCP — GCE VM | AWS — EC2 | AWS — ECS Fargate |
| --- | --- | --- | --- |
| **Service** | Compute Engine | EC2 | ECS Fargate |
| **Instance / size** | `e2-standard-4` | `m6i.xlarge` | 4 vCPU / 16 GB |
| **Compute rate** | ~$0.134 / hr | ~$0.192 / hr | ~$0.233 / hr ¹ |
| **Compute (960 h)** | ~$129 | ~$184 | ~$224 |
| **Storage** | 60 GB SSD PD (~$4) | 60 GB gp3 EBS (~$2) | None (ephemeral) |
| **Container registry** | Artifact Registry (~$0) ² | ECR (~$0) ² | ECR (~$0) ² |
| **Secrets** | Secret Manager (~$0) ³ | Secrets Manager (~$2) ⁴ | Secrets Manager (~$2) ⁴ |
| **Logging** | Cloud Logging (free tier) | CloudWatch Logs (~$1) ⁵ | CloudWatch Logs (~$1) ⁵ |
| **Total (approx.)** | **~$133** | **~$189** | **~$227** |
| **VM management** | Required | Required | None |
| **Auto-restart on failure** | Via startup script on reboot | Via Docker `--restart=unless-stopped` | Native (ECS desired count) |

> ¹ Fargate rate: $0.04048/vCPU/hr × 4 + $0.004445/GB/hr × 16 ≈ $0.233/hr.
>
> ² First 0.5 GB/month free for Artifact Registry; ECR first 50 GB/month free in
> the same region.
>
> ³ GCP Secret Manager: first 6 secret versions free; access operations well
> within the free tier for this workload.
>
> ⁴ AWS Secrets Manager: $0.40/secret/month × 4 secrets × ~1.3 months ≈ $2.
>
> ⁵ CloudWatch Logs: $0.50/GB ingested. Estimate assumes ~2 GB of log data over
> the ceremony window.

## Summary

- **GCP GCE** is the cheapest option (~$133) and provides the most
  straightforward setup for operators already in the GCP ecosystem.
- **AWS EC2** (~$189) is the closest equivalent on AWS and is the simpler AWS
  path — full VM access, familiar tooling.
- **AWS ECS Fargate** (~$227) is slightly more expensive due to the Fargate
  premium, but eliminates all VM management: no OS patching, no SSH access
  needed, and ECS handles restarts natively at the service level.
