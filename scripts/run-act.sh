#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Run nektos/act against the local Podman Docker-compatible API (not Docker Engine).
# Repo .actrc supplies network/image defaults.
#
# Usage:
#   scripts/run-act.sh
#   scripts/run-act.sh --job unit_tests
#   make act
#

set -euo pipefail

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PODMAN_SOCK="${SWM_ACT_PODMAN_SOCK:-${XDG_RUNTIME_DIR}/podman/podman.sock}"

if [[ ! -S "${PODMAN_SOCK}" ]]; then
    echo "ERROR: Podman API socket not found at ${PODMAN_SOCK}" >&2
    echo "Start it with: systemctl --user enable --now podman.socket" >&2
    echo "Or: podman system service --time=0 unix://${PODMAN_SOCK}" >&2
    exit 1
fi

export DOCKER_HOST="unix://${PODMAN_SOCK}"

exec act \
    --container-daemon-socket "${DOCKER_HOST}" \
    --concurrent-jobs 1 \
    "$@"
