#!/usr/bin/env bash

#set -o xtrace

SIM_CONFIG="/tmp/swm/priv/setup/dev2.config"
EXPECTED_NODES_IDLE=23
SWM_ROOT=/opt/swm

./test/prepare.sh -i ${SWM_ROOT} -s ${SIM_CONFIG} -n $EXPECTED_NODES_IDLE
if [ "$?" != "0" ]; then
  echo "ERROR: preparation for the test has failed"
  exit 1
fi

EXPECTED_ROUTE[1]="'chead1@$HOSTNAME'"
EXPECTED_ROUTE[2]="'phead1@$HOSTNAME'"
EXPECTED_ROUTE[3]="'phead4@$HOSTNAME'"
EXPECTED_ROUTE[4]="'node401@$HOSTNAME'"
EXPECTED_ROUTE[5]="'phead4@$HOSTNAME'"
EXPECTED_ROUTE[6]="'phead1@$HOSTNAME'"
EXPECTED_ROUTE[7]="'node101@$HOSTNAME'"
EXPECTED_ROUTE[8]="'phead1@$HOSTNAME'"
EXPECTED_ROUTE[9]="'phead4@$HOSTNAME'"
EXPECTED_ROUTE[10]="'node401@$HOSTNAME'"
EXPECTED_ROUTE[11]="'phead4@$HOSTNAME'"
EXPECTED_ROUTE[12]="'phead1@$HOSTNAME'"

. /usr/erlang/activate

# Set environment for user commands:
export SWM_SNAME=chead1
export SWM_API_PORT=10011
source ${SWM_ROOT}/current/scripts/swm.env

OUTPUT=$($SWM_CTL grid route node401 node101)

echo "-------------"
echo "OUTPUT="$OUTPUT
echo "-------------"

if [ "$OUTPUT" == "" ]; then
  exit 1
fi
LN=1
for LINE in $OUTPUT; do
  echo "LINE $LN: $LINE ${EXPECTED_ROUTE[$LN]}"
  if [[ $LINE != ${EXPECTED_ROUTE[$LN]} ]]; then
    echo "ERROR: expected ${EXPECTED_ROUTE[$LN]}, but got $LINE"
    exit 1
  fi
  let LN=$LN+1
done

exit 0

