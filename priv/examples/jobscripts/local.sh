#!/bin/sh
#
# Example: run a container on the same host where main Sky Port daemon runs.
#

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
