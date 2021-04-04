#!/usr/bin/env bash

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )

## Export variables
source ${ROOT_DIR}/scripts/swm.env


SWMCTL=${ROOT_DIR}/scripts/swmctl

function start_ghead() {
  erl -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_sasl -detached \
    -s swm -eval "dbg:tracer()." -eval "dbg:p(all, c)." -eval "dbg:tpl(wm_data, [])." -s swm
}

function start_sim_nodes() {
  cd ..
  $SWMCTL node startsim chead1
  sleep 1
  $SWMCTL node startsim phead1
  sleep 1
  $SWMCTL node startsim node001
  $SWMCTL node startsim node002
  $SWMCTL node startsim node003
}

start_ghead
sleep 1
start_sim_nodes

