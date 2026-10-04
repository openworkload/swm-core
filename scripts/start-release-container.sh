#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Start the Sky Port release pod:
#   pod skyport
#     skyport       -- prompt + swm-core under supervisord
#     skyport-gate  -- cloud gate under supervisord
#

set +x

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")
# shellcheck source=scripts/swm-pod-common.sh
source "${ROOT_DIR}/scripts/swm-pod-common.sh"

HOSTNAME=skyport
DOMAIN=openworkload.org
NETWORK=skyportnet
# Pod and container names must differ (podman rejects shared names).
POD_NAME=skyport-pod
CORE_NAME=skyport
GATE_NAME=skyport-gate
IMAGE_NAME=skyport:latest
GATE_API_PORT=8444
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PODMAN_SOCK="${SWM_CONTAINER_PODMAN_SOCK:-${XDG_RUNTIME_DIR}/podman/podman.sock}"
SKYPORT_USER=$(id -u -n)
SKYPORT_USER_ID=$(id -u)

PODMAN_MOUNT_ARGS=()
PODMAN_ENV_ARGS=()
if [ -S "${PODMAN_SOCK}" ]; then
    PODMAN_MOUNT_ARGS=(-v "${PODMAN_SOCK}:${PODMAN_SOCK}")
    PODMAN_ENV_ARGS=(
        -e "SWM_CONTAINER_PODMAN_SOCK=${PODMAN_SOCK}"
        -e "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    )
    echo "Mounting host Podman socket: ${PODMAN_SOCK}"
else
    echo "WARN: host Podman socket not found at ${PODMAN_SOCK}; local container jobs will fail until it is available" >&2
fi

swm_pod_ensure_release_pod_and_gate || exit 1

if ! podman container exists "${CORE_NAME}"; then
    echo "Creating release core container ${CORE_NAME} in pod ${POD_NAME} (interactive prompt)..."
    exec podman run \
        --pod "${POD_NAME}" \
        --name "${CORE_NAME}" \
        --volume "${HOME}/.ssh:${HOME}/.ssh" \
        --volume "${HOME}/.swm:${HOME}/.swm" \
        --volume "${HOME}/.cache/swm:/root/.cache/swm" \
        "${PODMAN_MOUNT_ARGS[@]}" \
        "${PODMAN_ENV_ARGS[@]}" \
        --workdir "${PWD}" \
        --tty \
        --interactive \
        -e "SKYPORT_USER=${SKYPORT_USER}" \
        -e "SKYPORT_USER_ID=${SKYPORT_USER_ID}" \
        "${IMAGE_NAME}"
fi

if [ "$(podman inspect -f '{{.State.Running}}' "${CORE_NAME}")" = "false" ]; then
    echo "Starting ${CORE_NAME}..."
    podman start "${CORE_NAME}"
else
    echo "${CORE_NAME} is already running (pod ${POD_NAME}, gate ${GATE_NAME})"
fi

exit 0
