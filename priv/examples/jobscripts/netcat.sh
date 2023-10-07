#!/bin/sh

#SWM name Netcat
#SWM relocatable
#SWM comment This is a simple netcat example of a job script
#SWM account openstack
#SWM flavor m1.medium
#SWM ports 1234/tcp
#SWM cloud-image ubuntu-22.04
#SWM container-image subfuzion/netcat
#SWM nodes 5

echo "Hello from job $SWM_JOBID"
date
pwd

timeout 360s netcat localhost 8888

exit 0
