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
# Ensure the skyport-dev container (same as `make cr`) is running, then start
# (or restart) swm-core and swm-cloud-gate inside it in the background. The
# script exits after launch; services keep running in the container.
#

set -euo pipefail

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")
GATE_DIR="${ROOT_DIR}/../swm-cloud-gate"

HOSTNAME=skyport
IMAGE_NAME=swm-build:29.1
DOCKER_SOCKET=/var/run/docker.sock
X11_SOCKET=/tmp/.X11-unix
CONTAINER_NAME=skyport-dev
NETWORK=skyportnet-dev
DOMAIN=openworkload.org
HOST_USER=${USER:-$(id -un)}

JUPUTER_HUB_API_PORT=8081
JUPUTER_HUB_PORT=8000
USER_API_PORT=8443
CORE_API_PORT=10001

GATE_LOG=/tmp/swm-cloud-gate-debug.log
SWM_CLOUD_GATE_CONFIG="${HOME}/.swm/cloud-gate.yaml"

in_container() {
    docker exec "${CONTAINER_NAME}" runuser -u "${HOST_USER}" -- bash -lc "$*"
}

ensure_network() {
    if docker network inspect "${NETWORK}" >/dev/null 2>&1; then
        echo "Docker network '${NETWORK}' already exists"
    else
        docker network create "${NETWORK}" >/dev/null
        echo "Created docker network '${NETWORK}'"
    fi
}

ensure_container() {
    # Same image/mounts/ports as scripts/start-debug-container.sh (`make cr`),
    # but keep the container detached instead of attaching an interactive shell.
    local running
    if ! running=$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null); then
        echo "Creating ${CONTAINER_NAME} (detached; same setup as make cr)..."
        docker run \
            -d \
            -v "${HOME}:${HOME}" \
            -v /etc/passwd:/etc/passwd \
            -v /etc/shadow:/etc/shadow \
            -v /etc/group:/etc/group \
            -v /opt:/opt \
            -v "${DOCKER_SOCKET}:${DOCKER_SOCKET}" \
            -v "${X11_SOCKET}:${X11_SOCKET}" \
            -e "DISPLAY=${DISPLAY:-}" \
            --name "${CONTAINER_NAME}" \
            --hostname "${HOSTNAME}" \
            --domainname "${DOMAIN}" \
            --network-alias "${HOSTNAME}.${DOMAIN}" \
            --workdir "${ROOT_DIR}" \
            --network "${NETWORK}" \
            -p "${CORE_API_PORT}:${CORE_API_PORT}" \
            -p "${USER_API_PORT}:${USER_API_PORT}" \
            -p "${JUPUTER_HUB_PORT}:${JUPUTER_HUB_PORT}" \
            -p "${JUPUTER_HUB_API_PORT}:${JUPUTER_HUB_API_PORT}" \
            "${IMAGE_NAME}" \
            sleep infinity
    elif [ "${running}" = "false" ]; then
        echo "Starting ${CONTAINER_NAME}..."
        docker start "${CONTAINER_NAME}" >/dev/null
    else
        echo "${CONTAINER_NAME} is already running"
    fi
}

swm_running() {
    in_container 'pgrep -x beam.smp >/dev/null 2>&1'
}

gate_running() {
    in_container 'ss -lntp 2>/dev/null | grep -q ":8444 "'
}

stop_swm() {
    if ! swm_running; then
        return 0
    fi
    echo "Stopping swm-core in ${CONTAINER_NAME}..."
    in_container "
        set -e
        source /usr/erlang/activate
        cd '${ROOT_DIR}'
        scripts/run-in-shell.sh -x -s || true
    "
    local i
    for i in $(seq 1 30); do
        if ! swm_running; then
            echo "swm-core stopped"
            return 0
        fi
        sleep 1
    done
    echo "WARN: swm-core still running after stop; killing beam.smp" >&2
    in_container 'pkill -x beam.smp || true'
    sleep 1
}

stop_gate() {
    if ! gate_running; then
        return 0
    fi
    echo "Stopping swm-cloud-gate in ${CONTAINER_NAME}..."
    in_container "
        pkill -f '${GATE_DIR}/run.py' 2>/dev/null || true
        pkill -f '${GATE_DIR}/run.sh' 2>/dev/null || true
        if ss -lntp 2>/dev/null | grep -q ':8444 '; then
            pid=\$(ss -lntp 2>/dev/null | awk '/:8444 / {match(\$0, /pid=[0-9]+/); if (RSTART) print substr(\$0, RSTART+4, RLENGTH-4)}' | head -1)
            if [ -n \"\$pid\" ]; then kill \"\$pid\" 2>/dev/null || true; fi
        fi
    "
    local i
    for i in $(seq 1 15); do
        if ! gate_running; then
            echo "swm-cloud-gate stopped"
            return 0
        fi
        sleep 1
    done
    echo "WARN: swm-cloud-gate still listening on :8444 after stop" >&2
}

start_swm() {
    if swm_running; then
        stop_swm
    fi
    echo "Starting swm-core in background..."
    in_container "
        set -e
        source /usr/erlang/activate
        cd '${ROOT_DIR}'
        export SWM_CLOUD_GATE_CONFIG='${SWM_CLOUD_GATE_CONFIG}'
        scripts/run-in-shell.sh -x -b
    "
    local i
    for i in $(seq 1 30); do
        if in_container "
            source /usr/erlang/activate
            cd '${ROOT_DIR}'
            scripts/run-in-shell.sh -x -p >/dev/null 2>&1
        "; then
            echo "swm-core is up (pong)"
            return 0
        fi
        sleep 1
    done
    echo "ERROR: swm-core did not respond to ping" >&2
    return 1
}

check_gate_venv() {
    # Require an existing venv; do not run `make prepare-venv` in the container.
    if [ ! -d "${GATE_DIR}" ]; then
        echo "ERROR: gate sources not found at ${GATE_DIR}" >&2
        return 1
    fi
    if [ ! -d "${GATE_DIR}/.venv" ]; then
        echo "ERROR: ${GATE_DIR}/.venv is missing." >&2
        echo "Create it on the host first (e.g. 'make prepare-venv' in swm-cloud-gate), then re-run." >&2
        return 1
    fi
}

start_gate() {
    if gate_running; then
        stop_gate
    fi
    echo "Starting swm-cloud-gate in background..."
    # Detached exec so the gate keeps running after this script exits.
    docker exec -d "${CONTAINER_NAME}" runuser -u "${HOST_USER}" -- bash -lc "
        cd '${GATE_DIR}'
        export SWM_GATE_CONFIG='${SWM_CLOUD_GATE_CONFIG}'
        exec bash run.sh >> '${GATE_LOG}' 2>&1
    "
    local i
    for i in $(seq 1 30); do
        if gate_running; then
            echo "swm-cloud-gate is up on :8444 (log: ${GATE_LOG} inside container)"
            return 0
        fi
        sleep 1
    done
    echo "ERROR: gate did not start listening on :8444; see ${GATE_LOG} in the container" >&2
    return 1
}

main() {
    cd "${ROOT_DIR}"
    check_gate_venv
    ensure_network
    ensure_container
    start_swm
    start_gate
    echo
    echo "Sky Port dev stack is running in ${CONTAINER_NAME} (services restarted if they were already up)."
    echo "  Attach shell:  make cr"
    echo "  swm log:       /opt/swm/spool/node@skyport.openworkload.org/log/"
    echo "  gate logs:     ${GATE_LOG} and /tmp/swm-cloud-gate.log (in container)"
}

main "$@"
