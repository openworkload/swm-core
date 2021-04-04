#/bin/bash

DOCKER=docker
IMAGE_NAME=swm-build:22.3

${DOCKER} build -t ${IMAGE_NAME} -f ./priv/build/Dockerfile .
echo "------------------------------------"
${DOCKER} images ${IMAGE_NAME}
