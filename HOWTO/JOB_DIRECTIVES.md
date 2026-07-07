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
This will request a partition with 3 compute nodes. The nodes will be named:
- `swm-<jobid>-main` (primary/manager node)
- `swm-<jobid>-node0` (first extra compute node)
- `swm-<jobid>-node1` (second extra compute node)

**Default:** 1 node

**Note:** Multi-node job support requires the gate to support the multi-node partition feature (available in swm-cloud-gate branch `feature/multi-node-jobs`).

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

```bash
#!/bin/bash

#SWM name Multi-Node MPI Job
#SWM nodes 4
#SWM flavor Standard_D4s_v3
#SWM cloud-image ubuntu22.04
#SWM container-image mpi/ubuntu:latest
#SWM relocatable
#SWM comment Distributed MPI computation across 4 nodes

echo "Starting multi-node job on $(hostname)"
echo "Job ID: $SWM_JOBID"

# Your MPI or distributed application code here
mpirun -n 16 ./my_parallel_app

echo "Job completed"
```
