# Job scripts

Job scripts in Sky Port are regular shell scripts that use special directives
prefixed with `#SWM` to specify job requirements and configuration.
Porter runs the script inside the job container (see `HOWTO/CONTAINERS.md`)
and exports `SWM_*` environment variables. From that script you can start
**tasks** with `swm-task` when the workload needs one or more processes across
the allocated nodes (for example MPI).

Job resource metrics (CPU / memory / optional GPU) are described in
`HOWTO/ACCOUNTING.md`.

## Available Directives

### Resource Requirements

#### nodes
Specify the number of nodes to allocate for the job.
```bash
#SWM nodes <count>
```
**Example:**
```bash
#SWM nodes 3
```
This requests a partition with 3 compute nodes. Names use the first 8 characters of the job id
(aligned with Azure VM names):
- `swm-<jobid8>-main` — primary/manager node (runs the job script)
- `swm-<jobid8>-compute1` — first extra compute node
- `swm-<jobid8>-compute2` — second extra compute node

**Default:** 1 node

**Note:** Multi-node partitions require a cloud gate that supports the `count` / multi-node feature (for example [swm-cloud-gate](https://github.com/openworkload/swm-cloud-gate) branch `feature/multi-node-jobs`).

#### flavor
Specify the cloud instance flavor/size.
```bash
#SWM flavor <flavor_name>
```

#### gpus
Request GPU resources.
```bash
#SWM gpus <count>
```

### Image Configuration

#### cloud-image
Specify the cloud VM image to use.
```bash
#SWM cloud-image <image_name>
```

#### container-image
OCI/Docker image to run the job in (via rootless Podman).
```bash
#SWM container-image <image:tag>
```

### Job Metadata

#### name
Set a human-readable name for the job.
```bash
#SWM name <job_name>
```

#### comment
Add a description/comment for the job.
```bash
#SWM comment <description>
```

#### account
Specify the account to use for billing.
```bash
#SWM account <account_name>
```

### Input/Output

#### stdin
Specify the standard input file.
```bash
#SWM stdin <file_path>
```

#### stdout
Specify where to redirect standard output of the **job script** (default `stdout.log` in the job workdir).
```bash
#SWM stdout <file_path>
```

Task processes spawned by `swm-task` do **not** append to this file; see [Task stdout and stderr](#task-stdout-and-stderr).

#### stderr
Specify where to redirect standard error of the **job script** (default `stderr.log` in the job workdir).
```bash
#SWM stderr <file_path>
```

Same separation applies for task processes; see [Task stdout and stderr](#task-stdout-and-stderr).

#### workdir
Set the working directory for the job.
```bash
#SWM workdir <directory_path>
```

#### input-files
Specify input files to be transferred to the job.
```bash
#SWM input-files <file1> <file2> ...
```

#### output-files
Specify output files to be transferred back after job completion.
```bash
#SWM output-files <file1> <file2> ...
```

### Networking

#### ports
Specify ports to forward from the remote node.
```bash
#SWM ports <port1>,<port2>,...
```

#### submission-address
Specify the submission address.
```bash
#SWM submission-address <address>
```

### Job Behavior

#### relocatable
Mark the job as relocatable (can be migrated between nodes).
```bash
#SWM relocatable
```

#### keep-resources
Keep remote cloud resources after the job finishes or is canceled (do not destroy the partition). Useful for debugging stuck or failed runs. Explicit job purge still destroys remote resources.
```bash
#SWM keep-resources
#SWM --keep-resources
```

## Environment Variables

Porter exports the following variables into the job script process. Values come from the job record (and related config) at start time.

| Variable | Description |
|---|---|
| `SWM_JOB_ID` | Job UUID |
| `SWM_JOB_NAME` | Job name (`#SWM name`) |
| `SWM_JOB_ACCOUNT` | Account name used for the job (`#SWM account`) |
| `SWM_JOB_NODES` | Comma-separated allocated node names; the partition manager (**main**) is always first |
| `SWM_JOB_NODES_NUMBER` | Number of allocated nodes (including main) |
| `SWM_JOB_COMMENT` | Job comment (`#SWM comment`) |
| `SWM_JOB_INPUT_FILES` | Comma-separated input files uploaded by SWM (`#SWM input-files`) |
| `SWM_JOB_OUTPUT_FILES` | Comma-separated output files downloaded when the job finishes (`#SWM output-files`) |
| `SWM_JOB_PORTS` | Ports to forward from the remote side (`#SWM ports`), as requested |
| `SWM_RELOCATABLE` | `YES` or `NO` — whether the job is relocatable (`#SWM relocatable`) |
| `SWM_KEEP_RESOURCES` | `YES` or `NO` — whether cloud resources are kept after finish/cancel (`#SWM keep-resources`) |

Empty lists/strings are exported as an empty value. User-defined pairs from the job `env` field are also applied; the `SWM_*` variables above always take precedence.

## Tasks (`swm-task`)

A **job** is the scheduled allocation plus the main job script (Porter on **main**).
A **task** is one workload chunk of that job — typically one process (or one MPI
rank) that should run on the allocated nodes.

Call `swm-task` from the job script inside the job container:

| Flag | Behavior |
|------|----------|
| (default) | Ask SWM (via **Porter control relay**) to spawn the command once per allocated node (one Porter container per node in v1) and wait in the foreground until all finish. |
| `--pmix` | Same multi-node spawn, plus per-node `swm-pmix` and `PMIX_*` / `SWM_PMIX_*` bootstrap env for MPI. |

`swm-task` never talks to Podman or SWM sockets directly. Inside containers only
**Porter** may communicate with SWM; `swm-task` uses the Unix socket path in
`SWM_PORTER_CTRL`.

Flow (with or without `--pmix`):

1. Main node already runs the job script in one Porter container.
2. `swm-task ./app` (or `swm-task --pmix ./app`) asks SWM through Porter to spawn ranks.
3. SWM creates **one Porter container per allocated node** and runs the command there.
4. With `--pmix`, SWM also starts per-node `swm-pmix` and injects `PMIX_*` / `SWM_*`.
5. `swm-task` stays in the foreground until all ranks finish; cancel tears down ranks (and `swm-pmix` if used).

### Task stdout and stderr

The job script and `swm-task` child processes use **separate** log files next to each other in the job workdir. That avoids concurrent NFS appends to one shared `stdout.log` / `stderr.log`.

| Writer | Stdout file | Stderr file |
|--------|-------------|-------------|
| Job script (main Porter) | `#SWM stdout` path, default `stdout.log` | `#SWM stderr` path, default `stderr.log` |
| Each `swm-task` process (task / rank `N`) | `stdout-taskN.log` (or `<basename>-taskN.<ext>` if `#SWM stdout` is customized) | `stderr-taskN.log` (same naming rule for `#SWM stderr`) |

Examples with the defaults (`stdout.log` / `stderr.log`) and three nodes (`N` = 0, 1, 2):

- `stdout.log`, `stderr.log` -- job script only
- `stdout-task0.log` .. `stdout-task2.log` -- one per task
- `stderr-task0.log` .. `stderr-task2.log` -- one per task

When the job finishes on cloud resources, SWM downloads the base logs and all present `*-taskN.log` files back to Skyport (into the job spool workdir). The HTTP APIs `/user/job/{id}/stdout` and `/user/job/{id}/stderr` return the job-script file plus each task file, separated by a line and labeled `Task N stdout:` / `Task N stderr:`.

See also `priv/examples/jobscripts/multiple-tasks-azure.sh` (plain `swm-task`),
`priv/examples/jobscripts/mpi-azure.sh` (`swm-task --pmix`), and
`priv/examples/jobscripts/nccl-azure-ib.sh` (Azure ND + NCCL over IB).

## Complete Multi-Node MPI Example

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
