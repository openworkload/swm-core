#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Shared helpers for Sky Port Podman pods (core + gate containers).
# Sourced by start-debug-container.sh, run-in-dev-container.sh,
# start-skyport-dev-bg.sh, and start-release-container.sh.
#

# shellcheck disable=SC2034

swm_pod_ensure_network() {
    local network="$1"
    if podman network inspect "${network}" >/dev/null 2>&1; then
        echo "Podman network '${network}' already exists"
    else
        podman network create "${network}" >/dev/null
        echo "Created podman network '${network}'"
    fi
}

# True if container exists and belongs to the named pod.
swm_pod_container_in_pod() {
    local container="$1"
    local pod="$2"
    local pod_id
    if ! podman container exists "${container}"; then
        return 1
    fi
    pod_id=$(podman inspect -f '{{.Pod}}' "${container}" 2>/dev/null || true)
    if [ -z "${pod_id}" ] || [ "${pod_id}" = "<no value>" ]; then
        return 1
    fi
    # Compare by pod name (inspect may return ID).
    local pod_name
    pod_name=$(podman pod inspect -f '{{.Name}}' "${pod_id}" 2>/dev/null || true)
    [ "${pod_name}" = "${pod}" ]
}

# Remove a pre-pod container (and empty pod name collision) so the stack can be recreated.
swm_pod_migrate_legacy_container() {
    local container="$1"
    local pod="$2"
    echo "WARN: container '${container}' exists outside pod '${pod}'; recreating as a pod stack..." >&2
    podman rm -f "${container}" >/dev/null 2>&1 || true
    # Drop a same-named leftover gate if present and also not in the pod.
    if [ -n "${GATE_NAME:-}" ] && podman container exists "${GATE_NAME}"; then
        if ! swm_pod_container_in_pod "${GATE_NAME}" "${pod}"; then
            podman rm -f "${GATE_NAME}" >/dev/null 2>&1 || true
        fi
    fi
    # If a pod with this name somehow exists without the core container, leave it;
    # ensure_pod / ensure_* will reuse or create as needed.
}

swm_pod_ensure_pod() {
    local pod="$1"
    local network="$2"
    local hostname_fqdn="$3"
    local short_alias="$4"
    shift 4
    # Remaining args: -p publish specs and optional --userns=...
    if podman pod exists "${pod}"; then
        echo "Pod '${pod}' already exists"
        return 0
    fi
    echo "Creating pod '${pod}' (hostname=${hostname_fqdn})..."
    podman pod create \
        --name "${pod}" \
        --hostname "${hostname_fqdn}" \
        --network "${network}" \
        --network-alias "${short_alias}" \
        --network-alias "${hostname_fqdn}" \
        --add-host=host:host-gateway \
        "$@"
}

swm_pod_start_if_stopped() {
    local name="$1"
    if [ "$(podman inspect -f '{{.State.Running}}' "${name}" 2>/dev/null)" = "false" ]; then
        echo "Starting ${name}..."
        podman start "${name}" >/dev/null
    fi
}

swm_pod_ensure_dev_stack() {
    # Args via globals expected by callers, or pass explicitly:
    #   POD_NAME CORE_NAME GATE_NAME IMAGE_NAME NETWORK HOSTNAME DOMAIN
    #   HOST_USER ROOT_DIR GATE_DIR HOME X11_SOCKET DISPLAY
    #   PODMAN_MOUNT_ARGS PODMAN_ENV_ARGS (arrays)
    #   CORE_API_PORT USER_API_PORT JUPUTER_HUB_PORT JUPUTER_HUB_API_PORT
    #   JOB_METRICS_PORT GATE_API_PORT
    local fqdn="${HOSTNAME}.${DOMAIN}"
    local gate_port="${GATE_API_PORT:-8444}"

    swm_pod_ensure_network "${NETWORK}"

    if podman container exists "${CORE_NAME}" && ! swm_pod_container_in_pod "${CORE_NAME}" "${POD_NAME}"; then
        swm_pod_migrate_legacy_container "${CORE_NAME}" "${POD_NAME}"
    fi
    if [ -n "${GATE_NAME:-}" ] && podman container exists "${GATE_NAME}" && ! swm_pod_container_in_pod "${GATE_NAME}" "${POD_NAME}"; then
        swm_pod_migrate_legacy_container "${GATE_NAME}" "${POD_NAME}"
    fi

    if ! podman image exists "${IMAGE_NAME}"; then
        echo "ERROR: image ${IMAGE_NAME} not found. Build it with: make build-debug-container" >&2
        return 1
    fi

    local prom_name="${PROM_NAME:-swm-prometheus}"
    local prom_image="${PROM_IMAGE:-docker.io/prom/prometheus:v2.55.1}"
    local prom_port="${PROM_PORT:-9090}"
    local prom_conf="${PROM_CONF:-${ROOT_DIR}/priv/container/prometheus/prometheus.yml}"
    local prom_vol="${PROM_VOLUME:-swm-prometheus-data}"

    if [ -n "${prom_name}" ] && podman container exists "${prom_name}" && ! swm_pod_container_in_pod "${prom_name}" "${POD_NAME}"; then
        swm_pod_migrate_legacy_container "${prom_name}" "${POD_NAME}"
    fi

    if ! podman pod exists "${POD_NAME}"; then
        echo "First create with --userns=keep-id may take several minutes (ID-mapped image layers)."
        swm_pod_ensure_pod "${POD_NAME}" "${NETWORK}" "${fqdn}" "${HOSTNAME}" \
            --userns=keep-id \
            --network-alias prometheus \
            -p "${CORE_API_PORT}:${CORE_API_PORT}" \
            -p "${USER_API_PORT}:${USER_API_PORT}" \
            -p "${JUPUTER_HUB_PORT}:${JUPUTER_HUB_PORT}" \
            -p "${JUPUTER_HUB_API_PORT}:${JUPUTER_HUB_API_PORT}" \
            -p "${JOB_METRICS_PORT}:${JOB_METRICS_PORT}" \
            -p "${gate_port}:${gate_port}" \
            -p "${prom_port}:${prom_port}"
    fi

    if ! podman container exists "${CORE_NAME}"; then
        echo "Creating core container ${CORE_NAME} in pod ${POD_NAME}..."
        # Do not mount host /etc/shadow (breaks sudo under --userns=keep-id).
        podman run \
            -d \
            --pod "${POD_NAME}" \
            --name "${CORE_NAME}" \
            -v "${HOME}:${HOME}" \
            -v /etc/passwd:/etc/passwd \
            -v /etc/group:/etc/group \
            -v /opt:/opt \
            "${PODMAN_MOUNT_ARGS[@]}" \
            -v "${X11_SOCKET}:${X11_SOCKET}" \
            -e "DISPLAY=${DISPLAY:-}" \
            "${PODMAN_ENV_ARGS[@]}" \
            --user "${HOST_USER}" \
            --workdir "${ROOT_DIR:-${PWD}}" \
            "${IMAGE_NAME}" \
            sleep infinity
    else
        swm_pod_start_if_stopped "${CORE_NAME}"
    fi

    if ! podman container exists "${GATE_NAME}"; then
        echo "Creating gate container ${GATE_NAME} in pod ${POD_NAME}..."
        podman run \
            -d \
            --pod "${POD_NAME}" \
            --name "${GATE_NAME}" \
            -v "${HOME}:${HOME}" \
            -v /etc/passwd:/etc/passwd \
            -v /etc/group:/etc/group \
            -v /opt:/opt \
            --user "${HOST_USER}" \
            --workdir "${ROOT_DIR:-${PWD}}" \
            -e "SWM_GATE_MODE=debug" \
            -e "SWM_CLOUD_GATE_CONFIG=${SWM_CLOUD_GATE_CONFIG:-${HOME}/.swm/cloud-gate.yaml}" \
            -e "SWM_GATE_DIR=${GATE_DIR}" \
            -e "HOME=${HOME}" \
            -e "USER=${HOST_USER}" \
            "${IMAGE_NAME}" \
            bash "${ROOT_DIR}/scripts/run-gate-supervisord.sh"
    else
        swm_pod_start_if_stopped "${GATE_NAME}"
    fi

    # Prometheus shares the pod netns: scrape SWM at 127.0.0.1:9568; SWM queries
    # http://127.0.0.1:9090 (or http://prometheus:9090 via pod network alias).
    # Run as root inside keep-id userns so the image can write its TSDB volume.
    if ! podman container exists "${prom_name}"; then
        if [[ ! -f "${prom_conf}" ]]; then
            echo "ERROR: Prometheus config not found: ${prom_conf}" >&2
            return 1
        fi
        echo "Creating Prometheus container ${prom_name} in pod ${POD_NAME}..."
        podman run \
            -d \
            --pod "${POD_NAME}" \
            --name "${prom_name}" \
            --user 0 \
            -v "${prom_conf}:/etc/prometheus/prometheus.yml:ro" \
            -v "${prom_vol}:/prometheus:U" \
            "${prom_image}" \
            --config.file=/etc/prometheus/prometheus.yml \
            --storage.tsdb.path=/prometheus \
            --storage.tsdb.retention.time=15d \
            --web.enable-lifecycle
    else
        swm_pod_start_if_stopped "${prom_name}"
    fi
}

# Create/start release pod + gate. Core is left to the caller (often -it for prompt).
swm_pod_ensure_release_pod_and_gate() {
    local fqdn="${HOSTNAME}.${DOMAIN}"
    local gate_port="${GATE_API_PORT:-8444}"
    local skyport_user="${SKYPORT_USER:-$(id -u -n)}"

    swm_pod_ensure_network "${NETWORK}"
    mkdir -p "${HOME}/.swm" 2>/dev/null || true

    if podman container exists "${CORE_NAME}" && ! swm_pod_container_in_pod "${CORE_NAME}" "${POD_NAME}"; then
        swm_pod_migrate_legacy_container "${CORE_NAME}" "${POD_NAME}"
    fi
    if [ -n "${GATE_NAME:-}" ] && podman container exists "${GATE_NAME}" && ! swm_pod_container_in_pod "${GATE_NAME}" "${POD_NAME}"; then
        swm_pod_migrate_legacy_container "${GATE_NAME}" "${POD_NAME}"
    fi

    if ! podman pod exists "${POD_NAME}"; then
        swm_pod_ensure_pod "${POD_NAME}" "${NETWORK}" "${fqdn}" "${HOSTNAME}" \
            -p 10001:10001 \
            -p 10002:10002 \
            -p 8443:8443 \
            -p "${gate_port}:${gate_port}" \
            -p 9568:9568
    fi

    if ! podman container exists "${GATE_NAME}"; then
        echo "Creating release gate container ${GATE_NAME} in pod ${POD_NAME}..."
        podman run \
            -d \
            --pod "${POD_NAME}" \
            --name "${GATE_NAME}" \
            --volume "${HOME}/.ssh:${HOME}/.ssh" \
            --volume "${HOME}/.swm:${HOME}/.swm" \
            -e "SWM_GATE_MODE=release" \
            -e "SWM_CLOUD_GATE_CONFIG=${HOME}/.swm/cloud-gate.yaml" \
            -e "SWM_GATE_USER=${skyport_user}" \
            -e "HOME=${HOME}" \
            "${IMAGE_NAME}" \
            /opt/swm/run-gate-supervisord.sh
    else
        swm_pod_start_if_stopped "${GATE_NAME}"
    fi
}
