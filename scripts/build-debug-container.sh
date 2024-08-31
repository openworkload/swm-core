#/bin/bash

DOCKER=docker
IMAGE_NAME=swm-build:24.2

${DOCKER} build -t ${IMAGE_NAME} -f ./priv/container/debug/Dockerfile .
echo "------------------------------------"
${DOCKER} images ${IMAGE_NAME}
