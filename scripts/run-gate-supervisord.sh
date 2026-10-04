#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Entrypoint for the cloud-gate container in a Sky Port pod.
# Waits for cloud-gate.yaml, renders supervisord_gate.conf, then runs supervisord
# in the foreground (PID 1) so the container stays up with the gate daemon.
#
# Env:
#   SWM_CLOUD_GATE_CONFIG  path to cloud-gate.yaml (required)
#   SWM_GATE_MODE          debug | release (default: release)
#   SWM_GATE_DIR           gate sources dir (debug mode; for supervisord directory=)
#   SWM_GATE_USER          username for template {{ USERNAME }} (release)
#   SWM_GATE_CONF_TEMPLATE optional path to supervisord_gate.conf template
#   SWM_GATE_CONF          rendered supervisord config path
#   SWM_GATE_WAIT_SECS     max seconds to wait for config (default: 3600)
#

set -euo pipefail

MODE="${SWM_GATE_MODE:-release}"
CONFIG="${SWM_CLOUD_GATE_CONFIG:-${HOME}/.swm/cloud-gate.yaml}"
WAIT_SECS="${SWM_GATE_WAIT_SECS:-3600}"
GATE_USER="${SWM_GATE_USER:-${USER:-root}}"

if [ "${MODE}" = "debug" ]; then
    ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    TEMPLATE="${SWM_GATE_CONF_TEMPLATE:-${ROOT_DIR}/priv/container/debug/supervisord_gate.conf}"
    CONF="${SWM_GATE_CONF:-/tmp/supervisord_gate.conf}"
    GATE_DIR="${SWM_GATE_DIR:-${ROOT_DIR}/../swm-cloud-gate}"
    export SWM_GATE_DIR
    export HOME="${HOME}"
    export SWM_CLOUD_GATE_CONFIG="${CONFIG}"
else
    TEMPLATE="${SWM_GATE_CONF_TEMPLATE:-/etc/supervisor/supervisord_gate.conf.template}"
    CONF="${SWM_GATE_CONF:-/etc/supervisor/conf.d/supervisord_gate.conf}"
fi

echo "Gate container: mode=${MODE} config=${CONFIG}"

i=0
while [ ! -f "${CONFIG}" ]; do
    if [ "${i}" -ge "${WAIT_SECS}" ]; then
        echo "ERROR: timed out waiting for ${CONFIG}" >&2
        exit 1
    fi
    if [ $((i % 15)) -eq 0 ]; then
        echo "Waiting for ${CONFIG} (${i}s)..."
    fi
    sleep 1
    i=$((i + 1))
done
echo "Found gate config: ${CONFIG}"

mkdir -p "$(dirname "${CONF}")"
sed \
    -e "s|{{ USERNAME }}|${GATE_USER}|g" \
    -e "s|{{ GATE_DIR }}|${GATE_DIR:-}|g" \
    "${TEMPLATE}" > "${CONF}"
echo "Rendered supervisord config: ${CONF}"

# Foreground: keep container alive while gate runs under supervisord.
exec supervisord -n -c "${CONF}" -l /tmp/supervisord-gate.log
