# Job Script Directives

Job scripts in Sky Port use special directives prefixed with `#SWM` to specify job requirements and configuration.

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

## Complete Multi-Node Example

See also `priv/examples/jobscripts/multi-node.job` for a full OpenMPI hello-world script.

For MPI (and similar), build a hostfile from the allocated node names. The job container runs on **main** with host networking; multi-host `mpirun` needs passwordless SSH (or an equivalent PMI launcher) between the partition hosts.

```bash
#!/bin/bash
set -euo pipefail

#SWM name Multi-node MPI example
#SWM nodes 3
#SWM relocatable
#SWM comment OpenMPI hello across the allocated partition nodes
#SWM flavor Standard_D4s_v3
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image ubuntu:24.04

HOSTFILE="${PWD}/hostfile"
IFS=',' read -r -a NODES <<< "${SWM_JOB_NODES}"

{
    for host in "${NODES[@]}"; do
        echo "${host} slots=1"
    done
} >"${HOSTFILE}"

# Install / compile OpenMPI app, then:
mpirun --hostfile "${HOSTFILE}" -np "${SWM_JOB_NODES_NUMBER}" ./mpi_hello
```