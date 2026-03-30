# Run on bare metal or VM (Linux or macOS)

## Hardware requirements

- CPU: 2 cores (4 threads)
- RAM: 16 GB
- Storage: 60 GB SSD
- Network: 1 Gbps

## Running the ceremony

> **Important:** all scripts must be run from the **project root directory**
> (i.e. the directory containing the README), not from a subdirectory.

### Production run

> **Note:** `scripts/baremetal/run-ceremony.sh` is currently a stub — production parameters are still to be defined. For now, you can run the test ceremony using `scripts/baremetal/run-test-ceremony.sh` as described in the next section.

```sh
./scripts/baremetal/run-ceremony.sh
```

### Test run

```sh
./scripts/baremetal/run-test-ceremony.sh
```

> **What to expect:** Your node takes a turn during each phase. Processing takes ~1 hour per turn
> on Apple Silicon (~2 hours on x86), plus upload time for ~6 GB of output. After completing
> phase 2, your node will move to phase 4 and wait for `initial.ready`. In the test
> environment (`tss-ceremony-testnet`), this is the expected end state — phase 4 requires a
> coordinator action that is not part of the test setup. A successful phase 2 completion confirms
> your entire setup is working correctly.

## Logs

Each run writes logs to `./logs/` on the host, mounted into the container at
`/app/logs/`. Files are named:

```plain
tss-ceremony.YYYYMMDDTHHmmSS.log
```

To follow the log:

```sh
tail -n +1 -f ./logs/$(ls -t ./logs/ | head -1)
```

## Checking podman resource usage

You can confirm the container is running and using the correct amount of resources with:

```bash
$ podman stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

NAME                              CPU %       MEM USAGE / LIMIT
hedera-tss-ceremony               6.95%       385MB / 16.72GB
```

## Stopping the ceremony

Run `podman stop hedera-tss-ceremony`.

The container uses
[`tini`](https://github.com/krallin/tini) as PID 1, which forwards `SIGTERM`
to the JVM for a graceful shutdown.
