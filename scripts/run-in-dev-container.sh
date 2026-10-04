#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Ensure skyport-dev is running (same mounts/ports as `make cr`), then run the
# given command inside it as the host user (never as root).
#
# Usage:
#   scripts/run-in-dev-container.sh 'make && make format'
#   scripts/run-in-dev-container.sh --stop-swm 'make && make worker'
#

set -euo pipefail

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")

HOSTNAME=skyport
IMAGE_NAME=swm-build:29.1
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PODMAN_SOCK="${SWM_CONTAINER_PODMAN_SOCK:-${XDG_RUNTIME_DIR}/podman/podman.sock}"
X11_SOCKET=/tmp/.X11-unix
CONTAINER_NAME=skyport-dev
NETWORK=skyportnet-dev
DOMAIN=openworkload.org
HOST_USER=${USER:-$(id -un)}

JUPUTER_HUB_API_PORT=8081
JUPUTER_HUB_PORT=8000
USER_API_PORT=8443
CORE_API_PORT=10001
JOB_METRICS_PORT=9568

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
            echo "  --stop-swm  stop SWM (beam) in the container before running the command" >&2
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
    # --userns=keep-id: do not use runuser (only root may); run as host user.
    podman exec --user "${HOST_USER}" "${CONTAINER_NAME}" bash -lc "$*"
}

swm_beam_alive() {
    # True only if a non-zombie beam.smp exists (container PID 1 often leaves
    # defunct beams after prior stops).
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
    if ! podman inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" >/dev/null 2>&1; then
        return 0
    fi
    if ! swm_beam_alive; then
        echo "SWM is not running in ${CONTAINER_NAME} (nothing to stop)"
        return 0
    fi
    echo "Stopping SWM in ${CONTAINER_NAME} before build (prevents sync vs compile races)..."
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

ensure_network() {
    if podman network inspect "${NETWORK}" >/dev/null 2>&1; then
        return 0
    fi
    podman network create "${NETWORK}" >/dev/null
    echo "Created podman network '${NETWORK}'"
}

ensure_container() {
    local running
    if ! running=$(podman inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null); then
        echo "Creating ${CONTAINER_NAME} (detached; same setup as make cr)..."
        # Do not mount host /etc/shadow (breaks sudo under --userns=keep-id).
        podman run \
            -d \
            -v "${HOME}:${HOME}" \
            -v /etc/passwd:/etc/passwd \
            -v /etc/group:/etc/group \
            -v /opt:/opt \
            "${PODMAN_MOUNT_ARGS[@]}" \
            -v "${X11_SOCKET}:${X11_SOCKET}" \
            -e "DISPLAY=${DISPLAY:-}" \
            "${PODMAN_ENV_ARGS[@]}" \
            --userns=keep-id \
            --name "${CONTAINER_NAME}" \
            --hostname "${HOSTNAME}" \
            --network-alias "${HOSTNAME}.${DOMAIN}" \
            --add-host=host:host-gateway \
            --workdir "${ROOT_DIR}" \
            --network "${NETWORK}" \
            -p "${CORE_API_PORT}:${CORE_API_PORT}" \
            -p "${USER_API_PORT}:${USER_API_PORT}" \
            -p "${JUPUTER_HUB_PORT}:${JUPUTER_HUB_PORT}" \
            -p "${JUPUTER_HUB_API_PORT}:${JUPUTER_HUB_API_PORT}" \
            -p "${JOB_METRICS_PORT}:${JOB_METRICS_PORT}" \
            --user "${HOST_USER}" \
            "${IMAGE_NAME}" \
            sleep infinity
    elif [ "${running}" = "false" ]; then
        echo "Starting ${CONTAINER_NAME}..."
        podman start "${CONTAINER_NAME}" >/dev/null
    fi
}

ensure_network
ensure_container

if [ "${STOP_SWM}" -eq 1 ]; then
    stop_swm_in_container
fi

echo "Running in ${CONTAINER_NAME} as ${HOST_USER}: ${CMD}"
exec podman exec --user "${HOST_USER}" "${CONTAINER_NAME}" bash -lc "
    set -e
    source /usr/erlang/activate
    # kerl activate points REBAR_CACHE_DIR at /usr/erlang/.cache/rebar3 (not
    # writable for a normal user). That breaks Hex/plugin fetches and can leave
    # deps like gun half-installed ({missing_module,gun_public_suffix}).
    export REBAR_CACHE_DIR=\"\${HOME}/.cache/rebar3\"
    mkdir -p \"\${REBAR_CACHE_DIR}\"
    cd '${ROOT_DIR}'
    ${CMD}
"
