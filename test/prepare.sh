#!/usr/bin/env bash

#set -o xtrace

if [ $# < 4 ]; then
    echo "Wrong number of arguments"
    exit 1
fi

while [[ $# -gt 1 ]]; do
    key="$1"
    case $key in
        -i)
          SWM_ROOT="$2"
          shift
          ;;
        -s)
          SIM_CONFIG="$2"
          shift
          ;;
        -n)
          EXPECTED_NODES_IDLE="$2"
          shift
          ;;
        *)
          ;;
    esac
    shift
done

. /usr/erlang/activate

rm -rf ${SWM_ROOT}/*
mkdir -p ${SWM_ROOT}
mkdir -p ${SWM_ROOT}/spool

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )
source ${ROOT_DIR}/scripts/swm.env

tar zfx _build/default/rel/swm/swm-${SWM_VERSION}.tar.gz -C $SWM_ROOT

SETUP_CONFIG=${SWM_ROOT}/${SWM_VERSION}/priv/setup/setup.config
echo "Setup config: $SETUP_CONFIG"



echo "=============== INSTALL GRID MANAGEMENT NODE =============="
${SWM_ROOT}/${SWM_VERSION}/scripts/setup-swm-core.py -v $SWM_VERSION -s $SWM_SPOOL -c ${SETUP_CONFIG} -d grid
echo
echo "=============== INSTALL CLUSTER MANAGEMENT NODE =============="
${SWM_ROOT}/${SWM_VERSION}/scripts/setup-swm-core.py -v $SWM_VERSION -s $SWM_SPOOL -c ${SETUP_CONFIG} -d cluster


function wait_swm() {
  attempt=0
  EXIT_CODE=1
  while [ $attempt -lt 10 ]; do
    echo "Ping attempt $attempt"
    ${SWM_ROOT}/${SWM_VERSION}/bin/swm ping
    if [ "$?" -eq "0" ]; then
      EXIT_CODE=0
      break
    fi
    (( attempt++ ))
    sleep 2
  done
  if [ "$EXIT_CODE" != "0" ]; then
    echo "Cluster management node is not pingable"
    exit $EXIT_CODE
  fi
}

function swm_command() {
  export SWM_API_PORT=$1
  export SWM_SNAME=$2
  export COMMAND=$3
  echo
  source ${ROOT_DIR}/scripts/swm.env
  echo "Do $COMMAND $SWM_SNAME ..."
  ${SWM_ROOT}/${SWM_VERSION}/bin/swm $COMMAND
  wait_swm
}

swm_command 10001 ghead start
swm_command 10011 chead1 start


echo
echo "Load additional configuration: ${SIM_CONFIG}"
${SWM_CTL} global import ${SIM_CONFIG}
swm_command 10011 chead1 restart # to reload wm_core with new parent


echo
sleep 10
CMD_RUN_SIM="${SWM_CTL} grid sim start"
echo "Run simulation: $CMD_RUN_SIM"
${SWM_CTL} grid sim start
if [ "$?" != "0" ]; then
    echo "Could not start simulation"
    exit 1
fi

echo "Waiting for idle allocation state for all the test nodes"

EXIT_CODE=1
TOTAL_ATTEMPTS=60
WAIT_SECONDS=5
for i in $(seq 1 $TOTAL_ATTEMPTS); do
    LINE=$(${SWM_CTL} grid show | grep NODES)
    if [ -z $EXPECTED_NODES_IDLE ]; then
      ALL_NODES=$(echo $LINE | awk '{print $3}')
    else
      ALL_NODES=$EXPECTED_NODES_IDLE
    fi
    IDLE_NODES=$(echo $LINE | awk '{print $4}')
    echo "[$i] Total: $ALL_NODES Idle: $IDLE_NODES"
    if [[ "$ALL_NODES" == "$IDLE_NODES" ]]; then
        EXIT_CODE=0
        break;
    fi
    sleep $WAIT_SECONDS
done

if [ "$EXIT_CODE" != "0" ]; then
    echo "Could not start all nodes in time"
    exit 1
fi

exit ${EXIT_CODE}
