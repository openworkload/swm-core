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

while [[ $# -gt 0 ]]
do
i="$1"

case $i in
    -e|--etop|etop)
    ETOP=true
    shift # past argument
    ;;
    -o|--observer|observer)
    OBSERVER=true
    shift # past argument
    ;;
    -g|--grid)
    export SWM_SNAME=ghead
    shift # past argument
    ;;
    -c|--cluster)
    export SWM_SNAME=chead1
    shift # past argument
    ;;
    -x|--skyport)
    export SWM_SNAME=node
    shift # past argument
    ;;
    -b|--background)
    BACKGROUND=true
    shift # past argument
    ;;
    -s|--stop)
    STOP=true
    shift # past argument
    ;;
    -p|--ping)
    PING=true
    shift # past argument
    ;;
    -h|--help)
    echo "The script starts erlang shell attached to a new swm instance"
    echo "Usage: ${0##*/} [-e|-o] [-g|c]"
    echo "  -x|--skyport                run in SkyPort mode"
    echo "  -e|--etop|etop              run etop in remote shell"
    echo "  -o|--observer|observer      run observer in remote shell"
    echo "  -g|--grid                   run (or connect to) grid SWM instance"
    echo "  -c|--cluster                run (or connect to) cluster SWM instance"
    echo "  -b|--background             run SWM instance in background mode"
    echo "  -s|--stop                   stop SWM instance"
    echo "  -p|--ping                   ping SWM instance"
    exit 0
    ;;
    *)
    shift # past argument
    ;;
esac
done

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )

## Export variables
source ${ROOT_DIR}/scripts/swm.env

## Use paths in source directory
export SWM_SCHED_EXEC=${ROOT_DIR}/../swm-sched/bin/swm-sched
export SWM_SCHED_LIB=${ROOT_DIR}/../swm-sched/bin
export SWM_DOCKER_VOLUMES_FROM=swm-dev:ro
export SWM_FINALIZE_IN_CONTAINER=${ROOT_DIR}/scripts/swm-docker-finalize.sh
export SWM_PORTER_IN_CONTAINER=${ROOT_DIR}/c_src/porter/swm-porter
export SWM_WORKER_LOCAL_PATH="${ROOT_DIR}/_build/packages/swm-worker.tar.gz"

VM_ARGS=$(grep -v -E '^#|^-name|^-sname|^-args_file' "${SWM_VM_ARGS}" | xargs | sed -e 's/ / /g')

HOSTNAME=$(hostname -f)
if [[ $HOSTNAME == *.* ]]; then
  ERL_NAME_ARG=-name
else
  ERL_NAME_ARG=-sname
fi

if [ $ETOP ]; then
  erl $ERL_NAME_ARG etop-`date +%s` ${VM_ARGS} -boot start_clean -remsh \'${SWM_SNAME}@$HOSTNAME\' \
    -s etop -output text -tracing off -sort msg_q -interval 1 -lines $( expr `tput lines` - 11 )
elif [ $OBSERVER ]; then
  erl $ERL_NAME_ARG observer-`date +%s` ${VM_ARGS} -boot start_clean -remsh \'${SWM_SNAME}@$HOSTNAME\' \
    -s observer
elif [ $STOP ]; then
  echo erl $ERL_NAME_ARG stop-`date +%s` ${VM_ARGS} -boot start_clean -noinput -noshell \
      -eval "io:format(\"~p~n\", [rpc:call('${SWM_SNAME}@$HOSTNAME', init, stop, [], 10000)]), halt(0)"
  erl $ERL_NAME_ARG stop-`date +%s` ${VM_ARGS} -boot start_clean -noinput -noshell \
      -eval "io:format(\"~p~n\", [rpc:call('${SWM_SNAME}@$HOSTNAME', init, stop, [], 10000)]), halt(0)"
elif [ $PING ]; then
  # TODO: get rid of the erlang distribution requirement
  erl $ERL_NAME_ARG ping-`date +%s` ${VM_ARGS} -boot start_clean -noinput -noshell \
      -eval "case {net_kernel:hidden_connect_node('${SWM_SNAME}@$HOSTNAME'), net_adm:ping('${SWM_SNAME}@$HOSTNAME')} of
               {true, pong} ->
                 timer:sleep(9000), %FIXME swm services are not always ready when pinged with net_adm:ping (use wm_pinger instead)
                 io:format(\"pong\n\", []),
                 halt(0);
               {_, pang} ->
                 io:format(\"Node ~p not responding to pings.\n\", ['${SWM_SNAME}@$HOSTNAME']),
                 halt(1)
             end"
elif [ $BACKGROUND ]; then
  erl $ERL_NAME_ARG $SWM_SNAME -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_sasl -detached \
    -s swm -s sync
else
  erl $ERL_NAME_ARG $SWM_SNAME -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_clean \
    -s swm -s sync
fi

