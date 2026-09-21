#!/bin/sh

#SWM name Simple multi-node job
#SWM comment This is a simplest example of a job script that requests multiple nodes
#SWM nodes 3
#SWM relocatable

#SWM account azure
#SWM flavor Standard_D2_v4
#SWM cloud-image ubuntu-hpc/2204
#SWM container-image swmregistry.azurecr.io/jupyter/pytorch-notebook:cuda12-hub-5.2.1
#SWM storage swmblobcontainer

cat /etc/os-release
sleep 120
echo "Hello from simple job $SWM_JOB_ID"
