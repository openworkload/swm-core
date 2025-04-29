#/bin/bash

DOCKER=docker
IMAGE_NAME=swm-build:27.3

${DOCKER} build -t ${IMAGE_NAME} -f ./priv/container/debug/Dockerfile .
echo "------------------------------------"
${DOCKER} images ${IMAGE_NAME}
