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

## Cleaning up after the ceremony

Once the ceremony is complete, remove the container and delete your private key
and certificate files:

```sh
./scripts/baremetal/clean-up-everything.sh
```

This stops and removes the `hedera-tss-ceremony` container and deletes all
`.pem` files from the `./keys/` directory. The script asks for confirmation
before proceeding.
