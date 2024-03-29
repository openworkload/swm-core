#!/usr/bin/env bash
#
# This script is used ti start a new docker container with swm inside or,
# if the container already exists, can start a new interactive bash session
# in the container.

function print_help() {
  echo "Usage: $0 [-i] [-s]"
  echo "  1) To run production swm-core container in background:"
  echo "    $0"
  echo "  2) To start swm-core container and run bash in it interactively and mount scrips directory:"
  echo "    $0 -i -s"
  echo
}

while getopts h:si flag
do
    case "${flag}" in
        h) print_help;;
        i) INTERACTIVE=1;;
        s) MOUNT_SCRIPTS=1;;
    esac
done

SWM_API_PORT=10001
SWM_HTTP_PORT=8443
CONTAINER_NAME=swm-core
IMAGE_NAME=swm-core:latest
DOCKER=docker
DOCKER_SOCKET=/var/run/docker.sock
X11_SOCKET=/tmp/.X11-unix
HOST_SPOOL=${HOME}/.swm-spool

HOST_IP=$(ip addr list ${BRIDGE} |grep "inet " |cut -d' ' -f6|cut -d/ -f1)
RUNNING=$(${DOCKER} inspect -f '{{.State.Running}}' ${CONTAINER_NAME})
INSPECTATION_CODE=$?

if [ $MOUNT_SCRIPTS ]; then
    EXTRA_MOUNTS="-v $PWD/scripts:/opt/swm/current/scripts"
fi

if [ ! -e ${HOST_SPOOL} ]; then
    mkdir -p ${HOST_SPOOL}
fi

if [ $INTERACTIVE ]; then
    if [ "$INSPECTATION_CODE" = "1" ]; then
        ${DOCKER} run\
            ${EXTRA_MOUNTS}\
            -v /opt/swm/current\
            -v $HOME/.swm:/root/.swm\
            -v ${HOST_SPOOL}:/opt/swm/spool\
            -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}\
            -v ${X11_SOCKET}:${X11_SOCKET}\
            -e DISPLAY=${DISPLAY}\
            --name ${CONTAINER_NAME}\
            --hostname $(hostname)\
            --domainname=openworkload.org\
            --add-host host:${HOST_IP}\
            --workdir ${PWD}\
            --tty\
            --interactive\
            --net bridge\
            -p $SWM_HTTP_PORT:$SWM_HTTP_PORT\
            -p $SWM_API_PORT:$SWM_API_PORT\
            ${IMAGE_NAME}\
            /bin/bash
    elif [[ ${RUNNING} = "false" ]]; then
        ${DOCKER} start ${CONTAINER_NAME}
    fi
    ${DOCKER} exec -ti ${CONTAINER_NAME} /bin/bash
fi

exit 0
