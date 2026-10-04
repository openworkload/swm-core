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

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
cd "${ROOT_DIR}"

PODMAN="${PODMAN:-podman}"
IMAGE_NAME="${SWM_DEBUG_IMAGE:-swm-build:29.1}"
CONTAINERFILE="${ROOT_DIR}/priv/container/debug/Containerfile"

if [[ ! -f "${CONTAINERFILE}" ]]; then
    echo "ERROR: Containerfile not found: ${CONTAINERFILE}" >&2
    exit 1
fi

echo "Building debug image ${IMAGE_NAME} from ${CONTAINERFILE}"
"${PODMAN}" build \
    --tag "${IMAGE_NAME}" \
    --file "${CONTAINERFILE}" \
    "${ROOT_DIR}"

# Short-name resolution may prefer docker.io/library/<name>; pin that too so
# scripts using IMAGE_NAME=swm-build:29.1 pick up the image just built.
case "${IMAGE_NAME}" in
    */*) ;;
    *)
        "${PODMAN}" tag "${IMAGE_NAME}" "docker.io/library/${IMAGE_NAME}"
        ;;
esac

if ! "${PODMAN}" image exists "${IMAGE_NAME}"; then
    echo "ERROR: build finished but image ${IMAGE_NAME} is missing" >&2
    exit 1
fi

echo "------------------------------------"
echo "Debug image in podman:"
"${PODMAN}" images "${IMAGE_NAME}"
