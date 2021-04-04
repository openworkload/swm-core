#!/bin/sh

#SWM name Transfer
#SWM relocatable
#SWM account_id a02bd1ce-60cb-11e8-a356-172ec08db3e9
#SWM comment This is a files transfer example job

#SWM workdir /tmp
#SWM input /tmp/input.dat
#SWM output results.dat

echo "Hello from transfer job $SWM_JOBID"
date
pwd
env | grep SWM

for i in $(seq 1 120); do
  echo $i;
  sleep 1;
done

tac ./input.dat > ./results.dat

exit 0
