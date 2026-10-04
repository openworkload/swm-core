#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Manage Prometheus inside skyport-dev-pod (not podman compose).
#
# Usage:
#   scripts/prometheus-in-pod.sh up
#   scripts/prometheus-in-pod.sh down
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
PROM_NAME=swm-prometheus
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
PROM_PORT=9090

PODMAN_MOUNT_ARGS=()
PODMAN_ENV_ARGS=()
if [ -S "${PODMAN_SOCK}" ]; then
    PODMAN_MOUNT_ARGS=(-v "${PODMAN_SOCK}:${PODMAN_SOCK}")
    PODMAN_ENV_ARGS=(
        -e "SWM_CONTAINER_PODMAN_SOCK=${PODMAN_SOCK}"
        -e "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
    )
fi

cmd="${1:-up}"
case "${cmd}" in
    up)
        # Existing pods created before Prometheus was added lack -p 9090:9090.
        # Recreate the pod once so the host can reach the Prometheus UI/API.
        if podman pod exists "${POD_NAME}"; then
            if ! podman pod inspect "${POD_NAME}" --format '{{json .InfraConfig.PortBindings}}' 2>/dev/null \
                | grep -q '"9090/tcp"'; then
                echo "Pod ${POD_NAME} has no host port 9090; recreating pod to publish Prometheus..."
                podman rm -f "${CORE_NAME}" "${GATE_NAME}" "${PROM_NAME}" 2>/dev/null || true
                podman pod rm -f "${POD_NAME}" 2>/dev/null || true
            fi
        fi
        swm_pod_ensure_dev_stack
        echo "Prometheus: http://127.0.0.1:${PROM_PORT} (container ${PROM_NAME} in pod ${POD_NAME})"
        ;;
    down)
        if podman container exists "${PROM_NAME}"; then
            echo "Stopping ${PROM_NAME}..."
            podman stop "${PROM_NAME}" >/dev/null
            echo "Stopped ${PROM_NAME} (pod ${POD_NAME} and other containers left running)"
        else
            echo "Prometheus container ${PROM_NAME} not found"
        fi
        ;;
    *)
        echo "Usage: $0 {up|down}" >&2
        exit 1
        ;;
esac
