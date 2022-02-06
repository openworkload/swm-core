#/bin/bash

set -x

DOCKER=docker
IMAGE_NAME=swm-build:24.2
DOCKER_SOCKET=/var/run/docker.sock
X11_SOCKET=/tmp/.X11-unix
CONTAINER_NAME=swm-dev
BRIDGE=docker0
HOST_IP=$(ip addr list ${BRIDGE} |grep "inet " |cut -d' ' -f6|cut -d/ -f1)

case "$(uname -s)" in
  Linux*)     ;;
  Darwin*)    USER=root;;
esac

JUPUTER_HUB_API_PORT=8081
JUPUTER_HUB_PORT=8000
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
    --hostname $(hostname)\
    --domainname=skyworkflows.com\
    --add-host host:${HOST_IP}\
    --workdir ${PWD}\
    --tty\
    --interactive\
    --net bridge\
    -p 10000:10000\
    -p 10011:10011\
    -p 8443:8443\
    -p $JUPUTER_HUB_PORT:$JUPUTER_HUB_PORT\
    -p $JUPUTER_HUB_API_PORT:$JUPUTER_HUB_API_PORT\
    ${IMAGE_NAME}\
    runuser -u ${USER} /bin/bash
else
  if [ ${RUNNING} = "false" ]; then
    ${DOCKER} start ${CONTAINER_NAME}
  fi
  ${DOCKER} exec -ti ${CONTAINER_NAME} runuser -u ${USER} /bin/bash
fi

