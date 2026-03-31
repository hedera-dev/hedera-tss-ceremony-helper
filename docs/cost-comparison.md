# Cost comparison for cloud services

**UNDER REVIEW** — AWS pricing and deployment paths may change.

All estimates assume a **40-day ceremony window** (960 hours) with resources
running continuously. Prices are on-demand rates in `us-east-1` / `us-central1`
as of early 2026 — check the official pricing pages for the most current figures.

| | GCP — GCE VM | AWS — EC2 |
| --- | --- | --- |
| **Service** | Compute Engine | EC2 |
| **Instance / size** | `e2-standard-4` | `m6i.xlarge` |
| **Compute rate** | ~$0.134 / hr | ~$0.192 / hr |
| **Compute (960 h)** | ~$129 | ~$184 |
| **Storage** | 60 GB SSD PD (~$4) | 60 GB gp3 EBS (~$2) |
| **Container registry** | Artifact Registry (~$0) ¹ | ECR (~$0) ¹ |
| **Secrets** | Secret Manager (~$0) ² | Secrets Manager (~$2) ³ |
| **Logging** | Cloud Logging (free tier) | CloudWatch Logs (~$1) ⁴ |
| **Total (approx.)** | **~$133** | **~$189** |
| **VM management** | Required | Required |
| **Auto-restart on failure** | Via startup script on reboot | Via Docker `--restart=unless-stopped` |

> ¹ First 0.5 GB/month free for Artifact Registry; ECR first 50 GB/month free in
> the same region.
>
> ² GCP Secret Manager: first 6 secret versions free; access operations well
> within the free tier for this workload.
>
> ³ AWS Secrets Manager: $0.40/secret/month × 4 secrets × ~1.3 months ≈ $2.
>
> ⁴ CloudWatch Logs: $0.50/GB ingested. Estimate assumes ~2 GB of log data over
> the ceremony window.

## Summary

- **GCP GCE** is the cheapest option (~$133) and provides the most
  straightforward setup for operators already in the GCP ecosystem.
- **AWS EC2** (~$189) is the closest equivalent on AWS — full VM access,
  familiar tooling.
