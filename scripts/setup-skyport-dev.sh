#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
  CONDITION=$1
  echo "Wait for Sky Port Daemon"
  while [ $attempt -lt 10 ]; do
    echo "Ping attempt $attempt"
    ${ROOT_DIR}/scripts/swm-ping localhost $SWM_API_PORT
    if [ "$CONDITION" == "started" ]; then
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

echo "Ensure symlink ~/.swm/spool --> /opt/swm/spool"
if [ ! -L "~/.swm/spool" ]; then
  ln -s /opt/swm/spool ~/.swm/spool
fi

echo
echo "Stop swm"
${ROOT_DIR}/scripts/run-in-shell.sh -x -s

echo
echo "Sky Port development setup has finished"
echo
