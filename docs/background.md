# Background

## What is a TSS Ceremony?

For TSS on Hedera ([HIP-1200](https://hips.hedera.com/hip/hip-1200)), a recursive zk-SNARK proof system is used to cryptographically validate the entire history of Hedera address books. Like most zk-SNARKs, this requires a one-time **trusted setup** to create a **Structured Reference String (SRS)** — a large set of public parameters that both provers and verifiers will use.

The SRS is generated through a collaborative ceremony where a set of parties (up to 20) take turns making contributions. The security guarantee is that as long as **at least one participant** is honest and destroys their private randomness after contributing, the SRS is secure and nobody can forge proofs. This is why having multiple independent participants matters — it removes single points of trust.

## How does the ceremony work?

The ceremony is **turn-based**: each participant acts when it is their turn. A single turn takes approximately 3 hours (with a 6-hour maximum timeout). All participants must remain **online for the entire ceremony window** (April 8 – May 12, 2026, ~40 days) because your turn can come at any time. Participants communicate through a shared GCP Cloud Storage bucket (accessed via S3-compatible API).

The output is the SRS plus a ceremony protocol transcript that allows public verification of the proceedings. After the ceremony, a public verification run confirms correctness, and participants must **destroy their private keys**.

> **Important:** a malicious or misbehaving participant forces the entire ceremony (~5–6 days of work) to restart. Follow all instructions carefully and do not modify ceremony parameters.

## How does the ceremony run?

The ceremony runs **disconnected from the Hedera network**. The only
connection required is between participants' machines and a shared Google Cloud Storage
bucket used to exchange data with other participants and the coordinator.

In detail:

1. Each participant is assigned a turn. Your machine **polls the GCP bucket** waiting for its turn.
2. When it is your turn, the program **downloads the output produced by the previous participants**.
3. It **applies its computation** on that payload, **signs the result**, and **uploads it** back to the bucket.
4. The next participant picks it up and repeats the process.

The ceremony has 5 phases. Participants operate on **phase 2 and phase 4** only;
the remaining phases are handled by the ceremony coordinator.

![Ceremony process diagram](ceremony-process.svg)

## What does this repository do?

This repository does **not** implement the cryptographic protocol. The ceremony logic lives in a pre-built Java application downloaded at container startup from a configurable URL (`JAR_URL` environment variable). By default, the container uses a test JAR from [GitHub Releases](https://github.com/hedera-dev/hedera-tss-ceremony-helper/releases) that validates S3 read/write permissions.

This repository provides:

- A **container image** (Podman/Docker) that downloads and runs the ceremony JAR automatically
- **Deployment scripts** for three platforms: bare metal/VM, GCP Compute Engine, and AWS (under review)
- **Key generation** tooling for the operator's participant IDentity
