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

set -x

DOCKER=docker
IMAGE_NAME=swm-build:24.2
DOCKER_SOCKET=/var/run/docker.sock
X11_SOCKET=/tmp/.X11-unix
CONTAINER_NAME=skyport-dev

case "$(uname -s)" in
  Linux*)     ;;
  Darwin*)    USER=root;;
esac

RUNNING=$(${DOCKER} inspect -f '{{.State.Running}}' ${CONTAINER_NAME})
if [ "$?" = "1" ]; then
  ${DOCKER} run\
    -v ${HOME}:${HOME}\
    -v /etc/passwd:/etc/passwd\
    -v /etc/shadow:/etc/shadow\
    -v /etc/group:/etc/group\
    -v /opt:/opt\
    -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}\
    -v ${X11_SOCKET}:${X11_SOCKET}\
    -e DISPLAY=${DISPLAY}\
    --name ${CONTAINER_NAME}\
    --hostname ${CONTAINER_NAME}.openworkload.org\
    --domainname openworkload.org\
    --workdir ${PWD}\
    --tty\
    --interactive\
    --net host\
    ${IMAGE_NAME}\
    runuser -u ${USER} /bin/bash

else
  if [ ${RUNNING} = "false" ]; then
    ${DOCKER} start ${CONTAINER_NAME}
  fi
  ${DOCKER} exec -ti ${CONTAINER_NAME} runuser -u ${USER} /bin/bash
fi

