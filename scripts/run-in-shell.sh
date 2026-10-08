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
    echo "  -p|--ping                   ping SWM instance (API / swm-ping)"
    exit 0
    ;;
    *)
    shift # past argument
    ;;
esac
done

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )

## Cookie policy (see HOWTO/SECURITY.md):
## - Daemon start: write a fresh random local cookie.
## - remsh tools (etop/observer): load the cookie the daemon wrote.
## - stop: prefer rpc with cookie; if missing, SIGTERM local beam (upgrade path).
## - API ping: no cookie required.
if [ "${PING}" = true ] || [ "${STOP}" = true ]; then
  export SWM_COOKIE_OPTIONAL=1
elif [ "${ETOP}" = true ] || [ "${OBSERVER}" = true ]; then
  :
else
  export SWM_REGENERATE_COOKIE=1
fi

## Export variables
source ${ROOT_DIR}/scripts/swm.env

## Scheduler: CI/act containers often only have swm-core (no sibling ../swm-sched).
## After `make release`, binaries are under _build/default/rel/swm/.
REL_SWM="${ROOT_DIR}/_build/default/rel/swm"
if [ -x "${REL_SWM}/bin/swm-sched" ]; then
  export SWM_SCHED_EXEC="${REL_SWM}/bin/swm-sched"
  export SWM_SCHED_LIB="${REL_SWM}/lib64"
else
  export SWM_SCHED_EXEC=${ROOT_DIR}/../swm-sched/bin/swm-sched
  export SWM_SCHED_LIB=${ROOT_DIR}/../swm-sched/bin
fi
## Porter is PID 1: do not inject tini. Override with SWM_CONTAINER_ENTRYPOINT if needed.
## Extra binds for Podman jobs: SWM_CONTAINER_EXTRA_BINDS=src:dst[:ro],...
## Prefer host Podman API when skyport-dev has the socket mounted (see start-debug-container.sh).
if [ -z "${SWM_CONTAINER_PODMAN_SOCK:-}" ]; then
  _podman_sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
  if [ -S "${_podman_sock}" ]; then
    export SWM_CONTAINER_PODMAN_SOCK="${_podman_sock}"
  fi
  unset _podman_sock
fi
export SWM_CONTAINER_FINALIZE="${SWM_CONTAINER_FINALIZE:-${ROOT_DIR}/scripts/swm-container-finalize.sh}"
export SWM_FINALIZE_IN_CONTAINER="${SWM_FINALIZE_IN_CONTAINER:-$SWM_CONTAINER_FINALIZE}"
export SWM_PORTER_IN_CONTAINER=${ROOT_DIR}/c_src/porter/swm-porter
export SWM_WORKER_LOCAL_PATH="${ROOT_DIR}/_build/packages/swm-worker.tar.gz"

HOSTNAME=$(hostname -f)
if [[ $HOSTNAME == *.* ]]; then
  ERL_NAME_ARG=-name
else
  ERL_NAME_ARG=-sname
fi

## VM args for short-lived remsh-style invocations (etop/observer/stop).
## They set their own -name/-sname on the command line, so any -name/-sname/
## -args_file in vm.args is filtered out to avoid duplicate-flag conflicts.
remsh_vm_args() {
  if [ -n "${SWM_COOKIE:-}" ] && [ -f "${SWM_VM_ARGS:-}" ]; then
    grep -v -E '^#|^-name|^-sname|^-args_file' "${SWM_VM_ARGS}" | xargs | sed -e 's/ / /g'
  fi
}

## Stop local SWM beams when dist rpc is unavailable (no cookie / wrong cookie).
stop_swm_beams() {
  local pid state cmdline killed=0
  for pid in $(pgrep -x beam.smp 2>/dev/null || true); do
    state=$(awk '{print $3}' "/proc/${pid}/stat" 2>/dev/null || true)
    if [ -z "${state}" ] || [ "${state}" = "Z" ]; then
      continue
    fi
    cmdline=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
    if echo "${cmdline}" | grep -Eq -- "(-sname|-name)[[:space:]]+${SWM_SNAME}(@|[[:space:]])|[[:space:]]${SWM_SNAME}[[:space:]]|/swm([[:space:]]|$)|bin/swm"; then
      echo "Stopping beam.smp pid=${pid} (${SWM_SNAME})"
      kill "${pid}" 2>/dev/null || true
      killed=1
    fi
  done
  if [ "${killed}" -eq 0 ]; then
    ## Broad fallback for older cmdline shapes / release scripts
    for pid in $(pgrep -x beam.smp 2>/dev/null || true); do
      state=$(awk '{print $3}' "/proc/${pid}/stat" 2>/dev/null || true)
      if [ -n "${state}" ] && [ "${state}" != "Z" ]; then
        echo "Stopping beam.smp pid=${pid} (fallback)"
        kill "${pid}" 2>/dev/null || true
        killed=1
      fi
    done
  fi
  ## Brief wait, then SIGKILL leftovers
  local i
  for i in 1 2 3 4 5; do
    pgrep -x beam.smp >/dev/null 2>&1 || return 0
    sleep 1
  done
  for pid in $(pgrep -x beam.smp 2>/dev/null || true); do
    state=$(awk '{print $3}' "/proc/${pid}/stat" 2>/dev/null || true)
    if [ -n "${state}" ] && [ "${state}" != "Z" ]; then
      echo "Force-killing beam.smp pid=${pid}"
      kill -9 "${pid}" 2>/dev/null || true
    fi
  done
}

## Log destination for the detached daemon (BACKGROUND mode). The Erlang
## logger handler in sys.config writes to ${SWM_LOG_DIR}/erlang.log only
## after the VM has booted far enough; anything earlier (boot errors, dist
## TLS misconfiguration, etc.) goes to stderr and must be captured here.
SWM_BG_LOG="${SWM_LOG_DIR}/run-in-shell.log"

if [ $ETOP ]; then
  VM_ARGS=$(remsh_vm_args)
  erl $ERL_NAME_ARG etop-`date +%s` ${VM_ARGS} -boot start_clean -remsh \'${SWM_SNAME}@$HOSTNAME\' \
    -s etop -output text -tracing off -sort msg_q -interval 1 -lines $( expr `tput lines` - 11 )
elif [ $OBSERVER ]; then
  VM_ARGS=$(remsh_vm_args)
  erl $ERL_NAME_ARG observer-`date +%s` ${VM_ARGS} -boot start_clean -remsh \'${SWM_SNAME}@$HOSTNAME\' \
    -s observer
elif [ $STOP ]; then
  if [ -n "${SWM_COOKIE:-}" ]; then
    VM_ARGS=$(remsh_vm_args)
    if [ -n "${VM_ARGS}" ]; then
      erl $ERL_NAME_ARG stop-`date +%s` ${VM_ARGS} -boot start_clean -noinput -noshell \
          -eval "io:format(\"~p~n\", [rpc:call('${SWM_SNAME}@$HOSTNAME', init, stop, [], 10000)]), halt(0)" \
        || true
    fi
  else
    echo "No local Erlang cookie at ${SWM_COOKIE_FILE:-$SWM_SPOOL/secure/cookie}; stopping via signal"
  fi
  stop_swm_beams
elif [ $PING ]; then
  exec "${ROOT_DIR}/scripts/swm-ping" "${SWM_API_HOST}" "${SWM_API_PORT}"
elif [ $BACKGROUND ]; then
  mkdir -p "$(dirname "${SWM_BG_LOG}")"
  : > "${SWM_BG_LOG}"
  ## Use nohup + redirected stdio instead of -detached so that boot-time
  ## errors (bad cert paths, dist TLS failures, port conflicts) land in
  ## ${SWM_BG_LOG} where wait_swm/CI can find them.
  nohup erl $ERL_NAME_ARG $SWM_SNAME -pa ${ROOT_DIR}/_build/default/lib/*/ebin \
    -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_sasl -noinput \
    -s swm -s sync \
    >> "${SWM_BG_LOG}" 2>&1 &
  disown $! 2>/dev/null || true
  echo "swm daemon backgrounded (pid=$!, log=${SWM_BG_LOG})"
else
  erl $ERL_NAME_ARG $SWM_SNAME -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_clean \
    -s swm -s sync
fi
