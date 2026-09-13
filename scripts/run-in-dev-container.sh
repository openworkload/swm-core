#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Ensure skyport-dev is running (same mounts/ports as `make cr`), then run the
# given command inside it as the host user via runuser (never as root).
#
# Usage: scripts/run-in-dev-container.sh 'make && make format'
#

set -euo pipefail

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")

HOSTNAME=skyport
IMAGE_NAME=swm-build:27.3
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

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <command>" >&2
    exit 1
fi
CMD=$*

ensure_network() {
    if docker network inspect "${NETWORK}" >/dev/null 2>&1; then
        return 0
    fi
    docker network create "${NETWORK}" >/dev/null
    echo "Created docker network '${NETWORK}'"
}

ensure_container() {
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
    fi
}

ensure_network
ensure_container

echo "Running in ${CONTAINER_NAME} as ${HOST_USER}: ${CMD}"
exec docker exec "${CONTAINER_NAME}" runuser -u "${HOST_USER}" -- bash -lc "
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
