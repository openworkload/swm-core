#!/bin/sh

# Example: run a container on the same host where SkyPort runs.
# Uses the localhost account/flavor on id-node-skyport (see skyport.config).
# That node needs the compute role so FCFS sees it as idle/schedulable.
# Do not set relocatable or cloud-image -- those allocate remote cloud VMs.
# Local allocation uses wm_compute -> Docker directly (no cloud gate / virtres).
#
# Prerequisites:
#   - SkyPort is running (e.g. make run-skyport)
#   - id-node-skyport has roles [cluster, compute] and flavor=localhost
#   - Docker daemon listens on TCP port 6000 (see HOWTO/INSTALL.md)
#   - For skyport-dev: SWM_CONTAINER_VOLUMES_FROM=skyport-dev:ro
#     (SWM_DOCKER_VOLUMES_FROM still accepted as alias; see HOWTO/CONTAINERS.md)
#   - Porter is PID 1 (no tini); see scripts/run-in-shell.sh
#   - Image is pullable on that Docker host
#
# Submit (after sourcing scripts/swm.env):
#   $SWM_JOB submit priv/examples/jobscripts/local.sh

#SWM name Local Container Job
#SWM comment Container on the SkyPort host (localhost account/flavor)
#SWM nodes 1
#SWM account localhost
#SWM flavor localhost
#SWM container-image ubuntu:24.04

set -eu

echo "Hello from local job ${SWM_JOB_ID}"
echo "Host: $(hostname)"
echo "Nodes: ${SWM_JOB_NODES}"
cat /etc/os-release
env | grep '^SWM_' || true
sleep 30
