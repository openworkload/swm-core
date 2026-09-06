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
This requests a partition with 3 compute nodes. Names use the first 8 characters of the job id:
- `swm-<jobid8>-main` — primary/manager node (runs the job script)
- `swm-<jobid8>-node0` — first extra compute node
- `swm-<jobid8>-node1` — second extra compute node

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
Specify the Docker container image to run the job in.
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

## Complete Multi-Node Example

See also `priv/examples/jobscripts/multi-node.job` for a full OpenMPI hello-world script.

For MPI (and similar), build a hostfile from the partition host names. The job container runs on **main** with host networking; multi-host `mpirun` needs passwordless SSH (or an equivalent PMI launcher) between the partition hosts. Porter sets `SWM_JOB_ID` in the job environment.

```bash
#!/bin/bash
set -euo pipefail

#SWM name Multi-node MPI example
#SWM nodes 3
#SWM relocatable
#SWM comment OpenMPI hello across the allocated partition nodes
#SWM flavor Standard_D4s_v3
#SWM cloud-image ubuntu-22.04
#SWM container-image ubuntu:22.04

NODES=3
JOB_PREFIX="swm-${SWM_JOB_ID:0:8}"
HOSTFILE="${PWD}/hostfile"

{
    echo "${JOB_PREFIX}-main slots=1"
    for i in $(seq 0 $((NODES - 2))); do
        echo "${JOB_PREFIX}-node${i} slots=1"
    done
} >"${HOSTFILE}"

# Install / compile OpenMPI app, then:
mpirun --hostfile "${HOSTFILE}" -np "${NODES}" ./mpi_hello
```
