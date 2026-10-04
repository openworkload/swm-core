#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Ensure the skyport-dev pod is running (same as `make cr`), then run the
# given command inside the core container as the host user (never as root).
#
# Usage:
#   scripts/run-in-dev-container.sh 'make && make format'
#   scripts/run-in-dev-container.sh --stop-swm 'make && make worker'
#

set -euo pipefail

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")
# shellcheck source=scripts/swm-pod-common.sh
source "${ROOT_DIR}/scripts/swm-pod-common.sh"

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
GATE_DIR="${ROOT_DIR}/../swm-cloud-gate"
SWM_CLOUD_GATE_CONFIG="${HOME}/.swm/cloud-gate.yaml"

JUPUTER_HUB_API_PORT=8081
JUPUTER_HUB_PORT=8000
USER_API_PORT=8443
CORE_API_PORT=10001
JOB_METRICS_PORT=9568
GATE_API_PORT=8444

PODMAN_MOUNT_ARGS=()
PODMAN_ENV_ARGS=()
if [ -S "${PODMAN_SOCK}" ]; then
    PODMAN_MOUNT_ARGS=(-v "${PODMAN_SOCK}:${PODMAN_SOCK}")
    PODMAN_ENV_ARGS=(
        -e "SWM_CONTAINER_PODMAN_SOCK=${PODMAN_SOCK}"
        -e "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    )
fi

STOP_SWM=0
ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --stop-swm)
            STOP_SWM=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--stop-swm] <command>" >&2
            echo "  --stop-swm  stop SWM (beam) in the core container before running the command" >&2
            echo "              (avoids sync hot-reload racing rebar3/make compile)" >&2
            exit 0
            ;;
        --)
            shift
            ARGS+=("$@")
            break
            ;;
        *)
            ARGS+=("$@")
            break
            ;;
    esac
done

if [ "${#ARGS[@]}" -lt 1 ]; then
    echo "Usage: $0 [--stop-swm] <command>" >&2
    exit 1
fi
CMD="${ARGS[*]}"

in_container() {
    podman exec --user "${HOST_USER}" "${CORE_NAME}" bash -lc "$*"
}

swm_beam_alive() {
    in_container '
        for pid in $(pgrep -x beam.smp 2>/dev/null); do
            state=$(awk "{print \$3}" /proc/$pid/stat 2>/dev/null || true)
            if [ -n "$state" ] && [ "$state" != "Z" ]; then
                exit 0
            fi
        done
        exit 1
    '
}

stop_swm_in_container() {
    if ! podman inspect -f '{{.State.Running}}' "${CORE_NAME}" >/dev/null 2>&1; then
        return 0
    fi
    if ! swm_beam_alive; then
        echo "SWM is not running in ${CORE_NAME} (nothing to stop)"
        return 0
    fi
    echo "Stopping SWM in ${CORE_NAME} before build (prevents sync vs compile races)..."
    in_container "
        set +e
        source /usr/erlang/activate
        cd '${ROOT_DIR}'
        scripts/run-in-shell.sh -x -s
        true
    " || true
    local i
    for i in $(seq 1 30); do
        if ! swm_beam_alive; then
            echo "SWM stopped"
            return 0
        fi
        sleep 1
    done
    echo "WARN: SWM still running after graceful stop; killing beam.smp" >&2
    in_container 'pkill -x beam.smp || true'
    sleep 1
    if swm_beam_alive; then
        echo "WARN: live beam.smp still present after pkill" >&2
        return 1
    fi
    echo "SWM stopped (forced)"
}

swm_pod_ensure_dev_stack || exit 1

if [ "${STOP_SWM}" -eq 1 ]; then
    stop_swm_in_container
fi

echo "Running in ${CORE_NAME} (pod ${POD_NAME}) as ${HOST_USER}: ${CMD}"
exec podman exec --user "${HOST_USER}" "${CORE_NAME}" bash -lc "
    set -e
    source /usr/erlang/activate
    export REBAR_CACHE_DIR=\"\${HOME}/.cache/rebar3\"
    mkdir -p \"\${REBAR_CACHE_DIR}\"
    cd '${ROOT_DIR}'
    ${CMD}
"
