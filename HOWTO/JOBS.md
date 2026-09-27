# Job scripts

Job scripts in Sky Port use special directives prefixed with `#SWM` to specify job
requirements and configuration. Porter runs the script inside the job container
(see `HOWTO/CONTAINERS.md`) and exports `SWM_*` environment variables. From that
script you can start **tasks** with `swm-task` when the workload needs one or
more processes across the allocated nodes (for example MPI).

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
Specify where to redirect standard output.
```bash
#SWM stdout <file_path>
```

#### stderr
Specify where to redirect standard error.
```bash
#SWM stderr <file_path>
```

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

Empty lists/strings are exported as an empty value. User-defined pairs from the job `env` field are also applied; the `SWM_*` variables above always take precedence.

## Tasks (`swm-task`)

A **job** is the scheduled allocation plus the main job script (Porter on **main**).
A **task** is one workload chunk of that job — typically one process (or one MPI
rank) that should run on the allocated nodes.

Call `swm-task` from the job script inside the job container:

| Flag | Behavior |
|------|----------|
| (default) | Run the given command **as-is** in the current container (`exec`). |
| `--pmix` | Enable PMIx. Ask SWM (via **Porter control relay** only) to start per-node `swm-pmix`, create one Porter container per rank (one rank per node in v1), and wait in the foreground until all ranks finish. |

`swm-task` never talks to Podman or SWM sockets directly. Inside containers only
**Porter** may communicate with SWM; `swm-task` uses the Unix socket path in
`SWM_PORTER_CTRL`.

Flow with `--pmix`:

1. Main node already runs the job script in one Porter container.
2. `swm-task --pmix ./app` asks SWM (through Porter) to start PMIx and rank containers.
3. SWM creates **one Porter container per rank** (v1: one rank per allocated node) and injects `PMIX_*` / `SWM_*`.
4. `swm-task` stays in the foreground until all ranks finish; cancel tears down ranks and `swm-pmix`.

Container lifecycle and host networking details: `HOWTO/CONTAINERS.md`. Tracker: GitHub issue #9.

## Complete Multi-Node MPI Example

See also `priv/examples/jobscripts/mpi.sh`.

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

# Host /opt is bind-mounted; expect OpenMPI at /opt/openmpi (no apt openmpi).
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
