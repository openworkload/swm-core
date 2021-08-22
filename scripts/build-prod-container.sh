#/bin/bash

#set -x

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )
DOCKERFILE=${ROOT_DIR}/priv/prod/Dockerfile

function print_help() {
    echo "Usage:"
    echo "  $0 -v 0.2.0"
    exit 0
}

while getopts v: flag
do
    case "${flag}" in
        h) print_help;;
        v) SWM_VERSION=${OPTARG};;
    esac
done

if [ -z $SWM_VERSION ]; then
    print_help
fi

echo "Building container for version ${SWM_VERSION} with ${DOCKERFILE}"

DOCKER=docker
IMAGE_NAME=swm-core
TAG=latest

${DOCKER} build -t ${IMAGE_NAME}:${SWM_VERSION} --build-arg SWM_VERSION=${SWM_VERSION} -f ${DOCKERFILE} .
${DOCKER} tag ${IMAGE_NAME}:${SWM_VERSION} ${IMAGE_NAME}:${TAG}

echo "------------------------------------"
echo "Created image:"
${DOCKER} images ${IMAGE_NAME}
