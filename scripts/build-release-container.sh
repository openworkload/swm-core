#/bin/bash
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

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )
DOCKERFILE=${ROOT_DIR}/priv/container/release/Dockerfile

SWM_VERSION=$(${ROOT_DIR}/scripts/version)
if [ -z "$SWM_VERSION" ]; then
    echo "ERROR: cannot fetch version from git, check script scripts/version"
    exit 1
fi

echo "Build container image: version=${SWM_VERSION}, dockerfile=${DOCKERFILE}"

DOCKER=docker
IMAGE_NAME=skyport
TAG=latest

CLOUD_GATE_VERSION=$(cd ../swm-cloud-gate/scripts > /dev/null; ./version)
GATE_PACKAGE_NAME=swmcloudgate-${CLOUD_GATE_VERSION}-py3-none-any.whl
GATE_PACKAGE_PATH_OLD=$ROOT_DIR/../swm-cloud-gate/dist/$GATE_PACKAGE_NAME
GATE_PACKAGE_PATH_NEW=_build/packages/$GATE_PACKAGE_NAME

echo "Copy $GATE_PACKAGE_PATH_OLD to $GATE_PACKAGE_PATH_NEW"
cp -f $GATE_PACKAGE_PATH_OLD $GATE_PACKAGE_PATH_NEW

${DOCKER} build --tag ${IMAGE_NAME}:${SWM_VERSION} \
                --build-arg SWM_VERSION=${SWM_VERSION} \
                --build-arg SWM_GATE_PACKAGE=$GATE_PACKAGE_PATH_NEW \
                --build-arg CACHEBUST=$(date +%s) \
                --file ${DOCKERFILE} .
${DOCKER} tag ${IMAGE_NAME}:${SWM_VERSION} ${IMAGE_NAME}:${TAG}

echo "------------------------------------"
echo "Sky Port image in docker:"
${DOCKER} images ${IMAGE_NAME}
