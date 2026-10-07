# Job scripts

Job scripts in Sky Port are shell scripts. They use special directives with the
`#SWM` prefix to set job requirements and configuration.

Porter runs the script inside the job container (see [CONTAINERS.md](CONTAINERS.md)).
Porter also exports `SWM_*` environment variables. From that script you can
start **tasks** with `swm-task` when the workload needs one or more processes
on the allocated nodes (for example MPI).

Job resource metrics (CPU, memory, and optional GPU) are in
[ACCOUNTING.md](ACCOUNTING.md). Optional DMTCP/MANA checkpointing is in
[CHECKPOINTS.md](CHECKPOINTS.md).

## Available directives

### Resource requirements

#### nodes

Set the number of nodes for the job.

```bash
#SWM nodes <count>
```

**Example:**

```bash
#SWM nodes 3
```

This request creates a partition with 3 compute nodes. Names use the first
8 characters of the job id (same length as Azure VM names):

- `swm-<jobid8>-main` -- primary/manager node (runs the job script)
- `swm-<jobid8>-compute1` -- first extra compute node
- `swm-<jobid8>-compute2` -- second extra compute node

**Default:** 1 node

**Note:** Multi-node partitions need a cloud gate that supports the `count` /
multi-node feature (for example
[swm-cloud-gate](https://github.com/openworkload/swm-cloud-gate) branch
`feature/multi-node-jobs`).

#### flavor

Set the cloud instance flavor (size).

```bash
#SWM flavor <flavor_name>
```

#### gpus

Request GPU resources.

```bash
#SWM gpus <count>
```

### Image configuration

#### cloud-image

Set the cloud VM image.

```bash
#SWM cloud-image <image_name>
```

#### container-image

Set the OCI/Docker image for the job (via rootless Podman).

```bash
#SWM container-image <image:tag>
```

### Job metadata

#### name

Set a human-readable name for the job.

```bash
#SWM name <job_name>
```

#### comment

Add a description for the job.

```bash
#SWM comment <description>
```

#### account

Set the account for billing.

```bash
#SWM account <account_name>
```

### Input and output

#### stdin

Set the standard input file.

```bash
#SWM stdin <file_path>
```

#### stdout

Set where to write standard output of the **job script**. The default is
`$SWM_SPOOL/job/<job-id>/stdout.log`. Relative paths are resolved under that
job log directory.

```bash
#SWM stdout <file_path>
```

Task processes from `swm-task` do **not** write to this file. See
[Task stdout and stderr](#task-stdout-and-stderr).

#### stderr

Set where to write standard error of the **job script**. The default is
`$SWM_SPOOL/job/<job-id>/stderr.log`. Relative paths are resolved under that
job log directory.

```bash
#SWM stderr <file_path>
```

The same separation applies to task processes. See
[Task stdout and stderr](#task-stdout-and-stderr).

#### workdir

Set the working directory for the job. The default is the job owner's `$HOME`.
The path must stay under the owner's home directory so SFTP upload and download
can reach it.

```bash
#SWM workdir <directory_path>
```

#### input-files

Set input files to transfer to the job.

```bash
#SWM input-files <file1> <file2> ...
```

#### output-files

Set output files to transfer back after the job completes.

```bash
#SWM output-files <file1> <file2> ...
```

### Networking

#### ports

Set ports to forward from the remote node.

```bash
#SWM ports <port1>,<port2>,...
```

#### submission-address

Set the submission address.

```bash
#SWM submission-address <address>
```

### Job behavior

#### relocatable

Mark the job as relocatable (the system can move it between nodes).

```bash
#SWM relocatable
```

#### keep-resources

Keep remote cloud resources after the job finishes or is canceled. Do not
destroy the partition. This helps when you debug stuck or failed runs. An
explicit job purge still destroys remote resources.

```bash
#SWM keep-resources
#SWM --keep-resources
```

#### checkpoint / checkpoint-dir / checkpoint-interval

Enable cancel-only DMTCP/MANA checkpointing. See [CHECKPOINTS.md](CHECKPOINTS.md).

```bash
#SWM checkpoint dmtcp
#SWM checkpoint-dir /mnt/blob/ckpt
#SWM checkpoint-interval 300
```

## Environment variables

Porter exports these variables into the job script process. Values come from
the job record (and related config) at start time.

| Variable | Description |
|---|---|
| `SWM_JOB_ID` | Job UUID |
| `SWM_JOB_NAME` | Job name (`#SWM name`) |
| `SWM_JOB_ACCOUNT` | Account name for the job (`#SWM account`) |
| `SWM_JOB_NODES` | Comma-separated allocated node names; the partition manager (**main**) is always first |
| `SWM_JOB_NODES_NUMBER` | Number of allocated nodes (including main) |
| `SWM_JOB_COMMENT` | Job comment (`#SWM comment`) |
| `SWM_JOB_INPUT_FILES` | Comma-separated input files that SWM uploaded (`#SWM input-files`) |
| `SWM_JOB_OUTPUT_FILES` | Comma-separated output files that SWM downloads when the job finishes (`#SWM output-files`) |
| `SWM_JOB_PORTS` | Ports to forward from the remote side (`#SWM ports`), as requested |
| `SWM_RELOCATABLE` | `YES` or `NO` -- whether the job is relocatable (`#SWM relocatable`) |
| `SWM_KEEP_RESOURCES` | `YES` or `NO` -- whether cloud resources stay after finish/cancel (`#SWM keep-resources`) |
| `SWM_CKPT` | Checkpoint engine (`dmtcp`) when `#SWM checkpoint` is set; empty when disabled |
| `SWM_CKPT_DIR` | Checkpoint image directory (`#SWM checkpoint-dir`) |
| `SWM_CKPT_INTERVAL` | Periodic checkpoint interval in seconds (`#SWM checkpoint-interval`; `0` = cancel-only) |

Empty lists and strings are exported as an empty value. User-defined pairs from
the job `env` field also apply. The `SWM_*` variables above always win.

## Tasks (`swm-task`)

A **job** is the scheduled allocation plus the main job script (Porter on
**main**). A **task** is one workload part of that job -- usually one process
(or one MPI rank) that must run on the allocated nodes.

Call `swm-task` from the job script inside the job container:

| Flag | Behavior |
|------|----------|
| (default) | Ask SWM (via **Porter control relay**) to start the command once on each allocated node (one Porter container per node in v1). Wait in the foreground until all finish. |
| `--pmix` | Same multi-node start, plus per-node `swm-pmix` and `PMIX_*` / `SWM_PMIX_*` bootstrap env for MPI. |

`swm-task` never talks to Podman or SWM sockets directly. Inside containers,
only **Porter** may talk to SWM. `swm-task` uses the Unix socket path in
`SWM_PORTER_CTRL`.

Flow (with or without `--pmix`):

1. The main node already runs the job script in one Porter container.
2. `swm-task ./app` (or `swm-task --pmix ./app`) asks SWM through Porter to start ranks.
3. SWM creates **one Porter container per allocated node** and runs the command there.
4. With `--pmix`, SWM also starts per-node `swm-pmix` and sets `PMIX_*` / `SWM_*`.
5. `swm-task` stays in the foreground until all ranks finish. Cancel stops ranks (and `swm-pmix` if used).

### Task stdout and stderr

The job script and `swm-task` child processes use **separate** log files under
`$SWM_SPOOL/job/<job-id>/`. This avoids concurrent NFS appends to one shared
`stdout.log` / `stderr.log`, and keeps logs out of the job workdir (`$HOME`).

| Writer | Stdout file | Stderr file |
|--------|-------------|-------------|
| Job script (main Porter) | `#SWM stdout` path, default `.../stdout.log` | `#SWM stderr` path, default `.../stderr.log` |
| Each `swm-task` process (task / rank `N`) | `stdout-taskN.log` (or `<basename>-taskN.<ext>` if `#SWM stdout` is set) | `stderr-taskN.log` (same naming rule for `#SWM stderr`) |

Examples with the defaults and three nodes (`N` = 0, 1, 2):

- `stdout.log`, `stderr.log` -- job script only
- `stdout-task0.log` .. `stdout-task2.log` -- one per task
- `stderr-task0.log` .. `stderr-task2.log` -- one per task

When the job finishes on cloud resources, SWM downloads the base logs and all
present `*-taskN.log` files back to Skyport (into `$SWM_SPOOL/job/<job-id>/`).
The HTTP APIs `/user/job/{id}/stdout` and `/user/job/{id}/stderr` return the
job-script file plus each task file. Files are separated by a line and labeled
`Task N stdout:` / `Task N stderr:`.

See also:

- `priv/examples/jobscripts/multiple-tasks-azure.sh` (plain `swm-task`)
- `priv/examples/jobscripts/mpi-azure.sh` (`swm-task --pmix`)
- `priv/examples/jobscripts/mpi-checkpoint-azure.sh` / `mpi-restart-azure.sh` (DMTCP/MANA)
- `priv/examples/jobscripts/nccl-azure-ib.sh` (Azure ND + NCCL over IB)

## Complete multi-node MPI example

See also `priv/examples/jobscripts/mpi-azure.sh`.

```bash
#!/bin/bash
set -euo pipefail

#SWM name Multi-node MPI example
#SWM nodes 3
#SWM relocatable
#SWM comment OpenMPI hello via swm-task --pmix (one rank per node)
#SWM flavor Standard_D4s_v3
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image ubuntu:24.04

export PATH="/opt/openmpi/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/openmpi/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cat >mpi_hello.c <<'EOF'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank = 0, size = 0, name_len = 0;
    char name[MPI_MAX_PROCESSOR_NAME];
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(name, &name_len);
    printf("Hello from MPI rank %d/%d on %s\n", rank, size, name);
    fflush(stdout);
    MPI_Finalize();
    return 0;
}
EOF

mpicc -o mpi_hello mpi_hello.c

# One rank per allocated node; PMIx server is owned by SWM (swm-pmix).
swm-task --pmix ./mpi_hello
```
