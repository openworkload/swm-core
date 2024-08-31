#/bin/bash

#set -x

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )
DOCKERFILE=${ROOT_DIR}/priv/container/release/Dockerfile

SWM_VERSION=$($ROOT_DIR/scripts/version)
if [ $SWM_VERSION == "" ]; then
    echo "ERROR: cannot fetch version from git, check script scripts/version"
    exit 1
fi

echo "Build container image: version=${SWM_VERSION}, dockerfile=${DOCKERFILE}"

DOCKER=docker
IMAGE_NAME=skyport
TAG=latest

GATE_PACKAGE_NAME=swmcloudgate-0.1.0-py3-none-any.whl
GATE_PACKAGE_PATH_OLD=$ROOT_DIR/../swm-cloud-gate/dist/$GATE_PACKAGE_NAME
GATE_PACKAGE_PATH_NEW=_build/packages/$GATE_PACKAGE_NAME
cp -f $GATE_PACKAGE_PATH_OLD $GATE_PACKAGE_DESTINATION_NEW

${DOCKER} build --tag ${IMAGE_NAME}:${SWM_VERSION} \
                --build-arg SWM_VERSION=${SWM_VERSION} \
                --build-arg SWM_GATE_PACKAGE=$GATE_PACKAGE_PATH_NEW \
                --file ${DOCKERFILE} .
${DOCKER} tag ${IMAGE_NAME}:${SWM_VERSION} ${IMAGE_NAME}:${TAG}

echo "------------------------------------"
echo "Created image:"
${DOCKER} images ${IMAGE_NAME}
