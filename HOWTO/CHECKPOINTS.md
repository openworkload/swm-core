# Job checkpointing (DMTCP / MANA)

Sky Port can checkpoint MPI jobs with **DMTCP** and **MANA** (MPI-Agnostic
Network-Agnostic checkpointing). Checkpointing is **optional**. You enable it
with `#SWM` directives.

Images such as Azure `ubuntu-hpc/2404` do **not** include DMTCP/MANA. When a
job requests checkpointing, the cloud gate installs them under `/opt` during
VM cloud-init.

See also [JOBS.md](JOBS.md) for general job scripts and
[CONTAINERS.md](CONTAINERS.md) for the Podman runtime.

## What is supported

| Item | Behavior |
|------|----------|
| Engine | DMTCP + MANA only |
| Trigger | **Cancel-only** final checkpoint (optional periodic interval while running) |
| Install | `/opt/mana` (includes DMTCP) via Azure cloud-init, **only if** `#SWM checkpoint dmtcp` |
| Images | Written under `#SWM checkpoint-dir` (prefer attached storage, for example `/mnt/blob/...`) |
| Requeue | **Not** supported -- cancel does not requeue the job |
| Restart | Submit a **new** job that runs `mana_restart` on the saved images |

## Directives

```bash
#SWM checkpoint dmtcp
#SWM checkpoint-dir /mnt/blob/ckpt/$SWM_JOB_ID
#SWM checkpoint-interval 300
#SWM storage swmblobcontainer
```

| Directive | Required | Meaning |
|-----------|----------|---------|
| `checkpoint dmtcp` | yes (to enable) | Enable DMTCP/MANA; starts `/opt` install on cloud VMs |
| `checkpoint-dir <path>` | recommended | Directory for checkpoint images (use attached blob mount) |
| `checkpoint-interval <sec>` | no | Periodic checkpoint while running; `0` or omit = cancel-only |
| `storage <name>` | recommended | Attach Azure blob storage (mounted at `/mnt/blob`) |

Without `#SWM checkpoint dmtcp`, checkpointing is **disabled**. The console
shows `disabled`. Cloud-init does **not** install MANA for those jobs.

## Environment variables

Porter exports these when checkpointing is enabled:

| Variable | Description |
|----------|-------------|
| `SWM_CKPT` | Engine name (`dmtcp`) when enabled; empty when disabled |
| `SWM_CKPT_DIR` | Checkpoint directory (`#SWM checkpoint-dir`) |
| `SWM_CKPT_INTERVAL` | Interval in seconds (`0` = cancel-only) |

Also put `/opt/mana/bin` (and DMTCP under that tree) on `PATH` inside the job
container. Host `/opt` is bind-mounted into job containers.

## Cancel-only checkpoint

1. The job runs under MANA (`mana_coordinator` + `mana_launch` / ranks).
2. The user cancels the job (API / console).
3. Sky Port asks the job main node to run a final checkpoint (`mana_status` /
   `dmtcp_command`) into `SWM_CKPT_DIR`.
4. On success, `last_checkpoint_time` is stored on the job (ISO-8601).
5. Normal cancel teardown continues (no requeue).

If the tools are missing or the coordinator is not reachable, cancel still
continues. `last_checkpoint_time` stays empty.

## Console / API

Job JSON includes:

- `checkpoint` -- engine string, or empty when disabled
- `checkpoint_dir`, `checkpoint_interval`
- `last_checkpoint_time` -- ISO-8601 of the last successful checkpoint, or empty

The console job overview shows **Checkpoint** as the last time, or **`disabled`**
when checkpointing was not requested.

## Cloud install (`/opt`)

For Azure partitions, when the create-partition request includes
`installcheckpointtools: true` (set by SWM from `#SWM checkpoint dmtcp`):

1. cloud-init builds and installs MANA into `/opt/mana` (DMTCP as submodule).
2. Install is skipped if `/opt/mana/bin/mana_launch` already exists.
3. First boot can take several minutes for the build.

Azure Marketplace image `microsoft-dsvm:ubuntu-hpc:2404` lists HPC-X, MPI,
PMIx, CUDA, and related tools, but **not** DMTCP/MANA. That is why install is
conditional.

## Job script pattern (launch)

```bash
#SWM checkpoint dmtcp
#SWM checkpoint-dir /mnt/blob/ckpt
#SWM storage swmblobcontainer

export PATH="/opt/mana/bin:${PATH}"
mkdir -p "${SWM_CKPT_DIR:-/mnt/blob/ckpt}"

mana_coordinator &
# wait for coordinator, then:
swm-task --pmix mana_launch ./mpi_app
```

See `priv/examples/jobscripts/mpi-checkpoint-azure.sh`.

## Restart (new job, no auto-requeue)

Cancel does not restart the job. To resume, submit a new job that points at the
same storage and runs `mana_restart`:

```bash
#SWM checkpoint dmtcp
#SWM checkpoint-dir /mnt/blob/ckpt
#SWM storage swmblobcontainer

export PATH="/opt/mana/bin:${PATH}"
mana_coordinator &
swm-task --pmix mana_restart --restartdir "${SWM_CKPT_DIR}"
```

See `priv/examples/jobscripts/mpi-restart-azure.sh`.

## Limitations

- Cancel-only orchestration in SWM. The job script must still start MANA at
  the application level.
- Periodic `#SWM checkpoint-interval` is recorded and exported as
  `SWM_CKPT_INTERVAL` for the job script / MANA. In this revision, SWM does
  not schedule the interval itself.
- The OpenStack cloud-init path does not install MANA yet (Azure only).
