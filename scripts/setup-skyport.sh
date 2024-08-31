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
#
# This script iitializes swm-core configuration.


function print_help() {
  echo "Usage: $0 [-u UID -g GID -n USERNAME]"
}

while getopts u:g:n:h flag
do
    case "${flag}" in
        h) print_help;;
        u) ARG_UID=${OPTARG};;
        g) ARG_GID=${OPTARG};;
        n) ARG_USER=${OPTARG};;
    esac
done

if [ $ARG_UID ]; then
    if [ -z $ARG_GID ]; then
        echo "Either all -u, -g and -n must be specified or neither of them."
        exit 1
    elif [ -z $ARG_USER ]; then
        echo "Either all -u, -g and -n must be specified or neither of them."
        exit 1
    fi
else
    ARG_UID=0
fi
if [ $ARG_GID ]; then
    if [ -z $ARG_UID ]; then
        echo "Either all -u, -g and -n must be specified or neither of them."
        exit 1
    elif [ -z $ARG_USER ]; then
        echo "Either all -u, -g and -n must be specified or neither of them."
        exit 1
    fi
else
    ARG_GID=0
fi
if [ $ARG_USER ]; then
    if [ -z $ARG_UID ]; then
        echo "Either all -u, -g and -n must be specified or neither of them."
        exit 1
    elif [ -z $ARG_GID ]; then
        echo "Either all -u, -g and -n must be specified or neither of them."
        exit 1
    fi
else
    ARG_USER=root
fi

export SWM_ROOT=/opt/swm
export SWM_VERSION_DIR=/opt/swm/current

source ${SWM_VERSION_DIR}/scripts/swm.env
export SWM_API_PORT=10001

mkdir -p /opt/swm/spool
cd /opt/swm/current

echo "Add group docker/${ARG_GID} and user ${ARG_USER}/${ARG_UID}:${ARG_GID}"
addgroup --gid ${ARG_GID} docker
if ! `id ${ARG_USER} 2>&1 > /dev/null`; then
    adduser --disabled-password --shell /bin/bash --uid ${ARG_UID} --gid ${ARG_GID} --quiet --gecos "" ${ARG_USER}
fi
chown -R ${ARG_UID}:${ARG_GID} /opt/swm/spool
chown -R ${ARG_UID}:${ARG_GID} ${SWM_VERSION_DIR}/log
chown -R ${ARG_UID}:${ARG_GID} ${SWM_VERSION_DIR}/releases

CONFIG_BASE=${SWM_VERSION_DIR}/priv/setup/setup.config
${SWM_VERSION_DIR}/scripts/setup-swm-core.py -n -x -v $SWM_VERSION -p $SWM_ROOT -s $SWM_SPOOL -c $CONFIG_BASE -d cluster -u $ARG_USER
EXIT_CODE=$?
if [ "$EXIT_CODE" != "0" ]; then
  echo "Cluster setup command failed with code $EXIT_CODE"
  exit $EXIT_CODE
fi

echo
echo "Sky Port setup has finished"
echo

exit 0
