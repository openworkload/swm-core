#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Ensure the skyport-dev pod is running, prepare the gate venv in the gate
# container, then start (or restart) swm-core in the core container.
# Cloud gate is managed by supervisord in skyport-dev-gate.
#

set -euo pipefail

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")
# shellcheck source=scripts/swm-pod-common.sh
source "${ROOT_DIR}/scripts/swm-pod-common.sh"

GATE_DIR="${ROOT_DIR}/../swm-cloud-gate"

HOSTNAME=skyport
IMAGE_NAME=swm-build:29.1
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PODMAN_SOCK="${SWM_CONTAINER_PODMAN_SOCK:-${XDG_RUNTIME_DIR}/podman/podman.sock}"
X11_SOCKET=/tmp/.X11-unix
POD_NAME=skyport-dev-pod
CORE_NAME=skyport-dev
GATE_NAME=skyport-dev-gate
NETWORK=skyportnet-dev
DOMAIN=openworkload.org
HOST_USER=${USER:-$(id -un)}

JUPUTER_HUB_API_PORT=8081
JUPUTER_HUB_PORT=8000
USER_API_PORT=8443
CORE_API_PORT=10001
JOB_METRICS_PORT=9568
GATE_API_PORT=8444

GATE_LOG=/tmp/swm-cloud-gate-debug.log
SWM_CLOUD_GATE_CONFIG="${HOME}/.swm/cloud-gate.yaml"

PODMAN_MOUNT_ARGS=()
PODMAN_ENV_ARGS=()
if [ -S "${PODMAN_SOCK}" ]; then
    PODMAN_MOUNT_ARGS=(-v "${PODMAN_SOCK}:${PODMAN_SOCK}")
    PODMAN_ENV_ARGS=(
        -e "SWM_CONTAINER_PODMAN_SOCK=${PODMAN_SOCK}"
        -e "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    )
else
    echo "WARN: host Podman socket not found at ${PODMAN_SOCK}; local container jobs will fail until it is available" >&2
fi

in_core() {
    podman exec --user "${HOST_USER}" "${CORE_NAME}" bash -lc "$*"
}

in_gate() {
    podman exec --user "${HOST_USER}" "${GATE_NAME}" bash -lc "$*"
}

swm_running() {
    in_core 'ps -C beam.smp -o pid=,stat= 2>/dev/null | awk '\''$2 !~ /^Z/ {found=1} END {exit !found}'\'''
}

gate_running() {
    # Shared netns with the pod -- check from either container.
    in_core 'ss -lntp 2>/dev/null | grep -q ":8444 "'
}

stop_swm() {
    if ! swm_running; then
        return 0
    fi
    echo "Stopping swm-core in ${CORE_NAME}..."
    in_core "
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
    echo "WARN: swm-core still running after stop; killing live beam.smp" >&2
    in_core '
        ps -C beam.smp -o pid=,stat= 2>/dev/null | awk '\''$2 !~ /^Z/ {print $1}'\'' | while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done
    '
    sleep 1
}

start_swm() {
    if swm_running; then
        stop_swm
    fi
    echo "Starting swm-core in background..."
    in_core "
        set -e
        source /usr/erlang/activate
        cd '${ROOT_DIR}'
        export SWM_CLOUD_GATE_CONFIG='${SWM_CLOUD_GATE_CONFIG}'
        scripts/run-in-shell.sh -x -b
    "
    local i
    for i in $(seq 1 30); do
        if in_core "
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

gate_python() {
    if in_gate 'command -v python3.12 >/dev/null 2>&1'; then
        echo python3.12
    elif in_gate 'command -v python3 >/dev/null 2>&1'; then
        echo python3
    else
        return 1
    fi
}

gate_venv_ok() {
    in_gate "
        cd '${GATE_DIR}' || exit 1
        test -x .venv/bin/python || exit 1
        .venv/bin/python -c 'import uvicorn' >/dev/null 2>&1
    "
}

prepare_gate_venv() {
    local py
    py=$(gate_python) || {
        echo "ERROR: no python3 in ${GATE_NAME}" >&2
        return 1
    }
    echo "Preparing swm-cloud-gate .venv inside ${GATE_NAME} (PYTHON=${py})..."
    in_gate "
        set -e
        cd '${GATE_DIR}'
        rm -rf .venv
        PYTHON='${py}' make prepare-venv
        .venv/bin/python -c 'import uvicorn'
    "
}

check_gate_venv() {
    if [ ! -d "${GATE_DIR}" ]; then
        echo "ERROR: gate sources not found at ${GATE_DIR}" >&2
        return 1
    fi
    if gate_venv_ok; then
        return 0
    fi
    echo "WARN: ${GATE_DIR}/.venv missing or not usable inside ${GATE_NAME} (often a host-built venv)." >&2
    prepare_gate_venv
}

wait_for_gate() {
    local i
    echo "Waiting for cloud gate on :8444 (supervisord in ${GATE_NAME})..."
    for i in $(seq 1 60); do
        if gate_running; then
            echo "swm-cloud-gate is up on :8444 (log: ${GATE_LOG} in ${GATE_NAME})"
            return 0
        fi
        sleep 1
    done
    echo "ERROR: gate did not start listening on :8444; check ${GATE_NAME} logs" >&2
    echo "  podman logs ${GATE_NAME}" >&2
    echo "  (gate waits for ${SWM_CLOUD_GATE_CONFIG} before starting supervisord)" >&2
    return 1
}

main() {
    cd "${ROOT_DIR}"
    swm_pod_ensure_dev_stack || exit 1
    check_gate_venv
    # Restart gate container so supervisord picks up a freshly prepared venv.
    if podman inspect -f '{{.State.Running}}' "${GATE_NAME}" 2>/dev/null | grep -q true; then
        echo "Restarting ${GATE_NAME} to reload gate supervisord..."
        podman restart "${GATE_NAME}" >/dev/null
    fi
    start_swm
    wait_for_gate
    echo
    echo "Sky Port dev stack is running in pod ${POD_NAME}."
    echo "  Core:   ${CORE_NAME}  (attach: make cr)"
    echo "  Gate:   ${GATE_NAME}  (supervisord)"
    echo "  swm log:  /opt/swm/spool/node@skyport.openworkload.org/log/"
    echo "  gate log: ${GATE_LOG} (in ${GATE_NAME})"
}

main "$@"
