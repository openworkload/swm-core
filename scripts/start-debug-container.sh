#!/bin/bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Start (or attach to) the Sky Port development pod:
#   pod skyport-dev-pod
#     skyport-dev       -- interactive / build shell (sleep infinity)
#     skyport-dev-gate  -- cloud gate under supervisord
#     swm-prometheus    -- Prometheus (host :9090)
#

set -x

ME=$(readlink -f "$0")
ROOT_DIR=$(dirname "$(dirname "$ME")")
# shellcheck source=scripts/swm-pod-common.sh
source "${ROOT_DIR}/scripts/swm-pod-common.sh"

HOSTNAME=skyport
IMAGE_NAME=swm-build:29.1
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PODMAN_SOCK="${SWM_CONTAINER_PODMAN_SOCK:-${XDG_RUNTIME_DIR}/podman/podman.sock}"
X11_SOCKET=/tmp/.X11-unix
# Pod and container names must differ (podman rejects shared names).
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
    echo "Mounting host Podman socket: ${PODMAN_SOCK}"
else
    echo "WARN: host Podman socket not found at ${PODMAN_SOCK}; local container jobs will fail until it is available" >&2
fi

swm_pod_ensure_dev_stack || exit 1

# Passwordless sudo for interactive debug sessions (core container only).
podman exec --user root "${CORE_NAME}" bash -lc "
set -euo pipefail
HOST_USER='${HOST_USER}'
if ! head -1 /etc/shadow >/dev/null 2>&1; then
    echo 'ERROR: /etc/shadow is not readable inside the container.' >&2
    echo 'Host /etc/shadow must not be bind-mounted when using --userns=keep-id.' >&2
    echo \"Recreate: podman rm -f ${CORE_NAME} ${GATE_NAME}; podman pod rm -f ${POD_NAME}; make cr\" >&2

    exit 1
fi
if [[ ! -f /etc/sudoers.d/nopasswd ]]; then
    echo 'ALL ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/nopasswd
    chmod 0440 /etc/sudoers.d/nopasswd
fi
days=\$((\$(date +%s) / 86400))
if ! grep -q \"^\${HOST_USER}:\" /etc/shadow; then
    echo \"\${HOST_USER}:*:\${days}:0:99999:7:::\" >> /etc/shadow
else
    sed -i -E \"s/^\${HOST_USER}:!+/\${HOST_USER}:*/\" /etc/shadow
fi
"
podman exec --user "${HOST_USER}" "${CORE_NAME}" sudo -n true

exec podman exec -ti --user "${HOST_USER}" "${CORE_NAME}" /bin/bash
