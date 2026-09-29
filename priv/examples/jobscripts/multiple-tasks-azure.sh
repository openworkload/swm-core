#!/bin/bash
set -euo pipefail

# Demonstrates plain swm-task (no --pmix): one process per allocated node.
# Per-node output lands in stdout-taskN.log (shown as "Task N stdout:" in the API/console).
#
#SWM name Multi-node task example
#SWM nodes 3
#SWM relocatable
#SWM comment Run a non-MPI task on every allocated node
#SWM flavor Standard_D2_v4
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image swmregistry.azurecr.io/openworkload/ubuntu:24.04
#SWM storage swmblobcontainer

echo "Job script on main: hostname=$(hostname) job=${SWM_JOB_ID:-?} nodes=${SWM_JOB_NODES_NUMBER:-?}"
echo "Spawning one task per allocated node..."

# One Porter/task container per job node; wait until all finish.
# Prefer lsb_release when present; otherwise /etc/os-release (minimal images often omit lsb-release).
swm-task bash -c 'cat /etc/os-release'
