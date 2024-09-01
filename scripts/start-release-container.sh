#!/usr/bin/env bash
#
# This script is used for running a new container with swm-core inside.

SWM_API_PORT=10001
SWM_HTTP_PORT=8443
CONTAINER_NAME=skyport
IMAGE_NAME=skyport:latest
DOCKER_SOCKET=/var/run/docker.sock

RUNNING=$(docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME} 2>/dev/null)
NOT_RUNNING=$?

if [ "$NOT_RUNNING" != "0" ]; then
    docker run\
        -v $HOME/.swm\
        -v $HOME/.cache\
        -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}\
        --name ${CONTAINER_NAME}\
        --hostname $(hostname)\
        --domainname=openworkload.org\
        --workdir ${PWD}\
        --tty\
        --interactive\
        --net bridge\
        -p $SWM_HTTP_PORT:$SWM_HTTP_PORT\
        -p $SWM_API_PORT:$SWM_API_PORT\
        ${IMAGE_NAME}
elif [[ ${RUNNING} = "false" ]]; then
    docker start ${CONTAINER_NAME}
fi

exit 0
