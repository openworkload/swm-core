#!/usr/bin/env bash

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )

CONFIG_BASE=${ROOT_DIR}/priv/setup/setup.config

mkdir -p /opt/swm/spool

## Export variables
source ${ROOT_DIR}/scripts/swm.env
export SWM_ROOT=$(pwd)
export SWM_VERSION_DIR=${SWM_ROOT}

echo
echo "=============== SETUP CLUSTER HEAD NODE ================"
export SWM_API_PORT=10011
${ROOT_DIR}/scripts/setup-swm-core.py -x -t -v $SWM_VERSION -p $SWM_ROOT -s $SWM_SPOOL -c $CONFIG_BASE -d cluster -u $USER
EXIT_CODE=$?
if [ "$EXIT_CODE" != "0" ]; then
  echo "Cluster setup command failed with code $EXIT_CODE"
  exit $EXIT_CODE
fi

echo
echo "=============== ADD EXTRA CONFIG ================"

function wait_swm() {
  attempt=0
  EXIT_CODE=1
  DIV=$1
  COND=$2
  while [ $attempt -lt 10 ]; do
    echo "Ping attempt $attempt"
    ${ROOT_DIR}/scripts/run-in-shell.sh ${DIV} -p
    if [ "$COND" == "started" ]; then
      if [ "$?" == "0" ]; then
        EXIT_CODE=0
        break
      fi
    else
      if [ "$?" != "0" ]; then
        EXIT_CODE=0
        break
      fi
    fi
    (( attempt++ ))
    sleep 2
  done
  if [ "$EXIT_CODE" != "0" ]; then
    echo "Cluster management node is not pingable"
    exit $EXIT_CODE
  fi
}

wait_swm -x stopped

echo
CMD="${ROOT_DIR}/scripts/run-in-shell.sh -x -b"
echo "Run $CMD"
$CMD
EXIT_CODE=$?
if [ "$EXIT_CODE" != "0" ]; then
  echo "Could not start swm in background ($EXIT_CODE)"
  exit $EXIT_CODE
fi

echo
echo "Wait for swm"
wait_swm -x started

function import_config() {
  CONFIG=$1
  echo
  CMD="${ROOT_DIR}/scripts/swmctl global import ${CONFIG}"
  echo "Run $CMD"
  $CMD
  EXIT_CODE=$?
  if [ "$EXIT_CODE" != "0" ]; then
    echo "Could not import extra config ($EXIT_CODE)"
    exit $EXIT_CODE
  fi
}

# TODO: create sym links to porter and other scripts in /opt/swm from sources
echo "Create symlink ~/.swm/spool --> /opt/swm/spool"
ln -s /opt/swm/spool ~/.swm/spool

echo
echo "Stop swm"
${ROOT_DIR}/scripts/run-in-shell.sh -x -s

echo
echo "Sky Port development setup has finished"
echo
