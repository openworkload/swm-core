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
# This script is used for running Sky Port containers

set +x

HOSTNAME=skyport
DOMAIN=openworkload.org
NETWORK=skyportnet

CONTAINER_NAME=skyport
#IMAGE_NAME=openworkload/skyport:latest
IMAGE_NAME=skyport:latest
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PODMAN_SOCK="${SWM_CONTAINER_PODMAN_SOCK:-${XDG_RUNTIME_DIR}/podman/podman.sock}"

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

RUNNING=$(podman inspect -f '{{.State.Running}}' ${CONTAINER_NAME} 2>/dev/null)
NOT_RUNNING=$?

if podman network inspect "${NETWORK}" >/dev/null 2>&1; then
    echo "Podman network '${NETWORK}' already exists"
else
    podman network create "${NETWORK}" >/dev/null
    echo "Created podman network '${NETWORK}'"
fi

mkdir -p $HOME/.swm 2>/dev/null

if [ "$NOT_RUNNING" != "0" ]; then
    podman run\
        --volume $HOME/.ssh:$HOME/.ssh\
        --volume $HOME/.swm:$HOME/.swm\
        --volume $HOME/.cache/swm:/root/.cache/swm\
        "${PODMAN_MOUNT_ARGS[@]}"\
        "${PODMAN_ENV_ARGS[@]}"\
        --name ${CONTAINER_NAME}\
        --hostname ${HOSTNAME}.${DOMAIN}\
        --network-alias ${HOSTNAME}\
        --network-alias ${HOSTNAME}.${DOMAIN}\
        --add-host=host:host-gateway\
        --workdir ${PWD}\
        --tty\
        --interactive\
        --network $NETWORK\
        -e SKYPORT_USER=$(id -u -n)\
        -e SKYPORT_USER_ID=$(id -u)\
        ${IMAGE_NAME}

elif [[ ${RUNNING} = "false" ]]; then
    podman start ${CONTAINER_NAME}
fi

exit 0
