#!/usr/bin/env bash

IMAGE_TAG="22.3"
IMAGE=swm-build:${IMAGE_TAG}

case "$(uname -s)" in
  Linux*)     READLINK="readlink -f"
              ;;
  Darwin*)    USER=root
              READLINK=realpath
              ;;
esac

ME=$($READLINK "$0")
MY_DIR=$( cd "$( dirname "$ME" )" && pwd )
SWM_SRC_ROOT=$( dirname "$MY_DIR" )
SWM_SCHED_SRC_ROOT=$( dirname "$SWM_SRC_ROOT" )"/swm-sched"

SWM_SRC_IN_CONTAINER=/tmp/swm
SCHED_SRC_IN_CONTAINER=/tmp/swm-sched

BUILD_CMD="$SWM_SRC_IN_CONTAINER/priv/build/build-package.sh $UID $USER"
TESTS_ROOT=$SWM_SRC_ROOT/test
TESTS_SCHED_ROOT=$SWM_SRC_ROOT/../swm-sched/tests

MOUNT_SWM="-v $SWM_SRC_ROOT:/tmp/swm -v $SWM_SCHED_SRC_ROOT:/tmp/swm-sched"
MOUNT_ETC="-v /etc/shadow:/etc/shadow -v /etc/group:/etc/group -v /etc/passwd:/etc/passwd"

SET_HOSTNAME="-h test.skyworkflows.com"
DOCKER_SOCKET=/var/run/docker.sock
TMP_DIR=/tmp
BRIDGE=docker0
HOST_IP=$(ip addr list ${BRIDGE} | grep "inet " |cut -d' ' -f6|cut -d/ -f1)
X11_SOCKET=/tmp/.X11-unix

echo
echo "SWM path (host): $SWM_SRC_ROOT"
echo "SWM path (container): $SWM_SRC_IN_CONTAINER"
echo "SWM-SCHED path (host): $SWM_SCHED_SRC_ROOT"
echo "SWM-SCHED path (container): $SCHED_SRC_IN_CONTAINER"

# Build base image that can be used for sources compilation
echo
echo "============================================================== [1] BUILD IMAGE"
cd $SWM_SRC_ROOT
echo "Build docker image ${IMAGE}"
echo
docker build -t ${IMAGE} -f priv/build/Dockerfile .
if [ "$?" != "0" ]; then
    echo "FAIL"
    exit 1
fi

# Build SWM from sources
echo
echo "============================================================== [2] BUILD SWM"
cd $SWM_SRC_ROOT
echo "Build SWM using image ${IMAGE} (PWD="$(pwd)")"
echo
echo "Going to execute in container:"
echo "  # ${BUILD_CMD}"
docker run ${MOUNT_SWM} -ti ${IMAGE} ${SHELL} -c "${BUILD_CMD}"
if [ "$?" != "0" ]; then
    echo "FAIL"
    exit 1
fi

# Run tests script inside the 1st container
echo
echo "============================================================== [3] RUN TESTS"
echo "Run tests script inside the container with image ${IMAGE}"

if [ ! -d $TESTS_ROOT ]; then
  echo "ERROR: no such directory: $TESTS_ROOT"
  echo "FAIL"
  exit 1
fi

if [ ! -d $TESTS_SCHED_ROOT ]; then
  echo "ERROR: no such directory: $TESTS_SCHED_ROOT"
  echo "FAIL"
  exit 1
fi

i=0
declare -a TEST_NAMES
declare -a TEST_RESULTS

for ABS_DIR in $($READLINK $TESTS_ROOT/*); do
    REPO_NAME=$(basename $(dirname $(dirname ${ABS_DIR})))
    DIR=$(basename ${ABS_DIR})
    if [ -d $ABS_DIR ]; then
        echo "Consider test directory $ABS_DIR"
        TEST_SCRIPT_IN_CONT="/tmp/${REPO_NAME}/test/$DIR/run.sh $USER"
        echo
        echo "------------- RUN TEST $i [$DIR] ---------------"
        echo
        echo "Going to execute in container:"
        echo "  ${TEST_SCRIPT_IN_CONT}"
        echo
        docker run\
            ${SET_HOSTNAME} \
            ${MOUNT_ETC}\
            ${MOUNT_SWM} \
            -v ${TMP_DIR}:${TMP_DIR}\
            -v ${HOME}:${HOME}\
            -v ${DOCKER_SOCKET}:${DOCKER_SOCKET}\
            -v ${X11_SOCKET}:${X11_SOCKET}\
            -e DISPLAY=${DISPLAY}\
            --add-host host:${HOST_IP}\
            --tty\
            --interactive\
            --net bridge\
            ${IMAGE}\
            ${TEST_SCRIPT_IN_CONT}
        TEST_RESULTS[${i}]="$?"
        TEST_NAMES[${i}]="${DIR}"
        let i=$i+1
    fi
done

echo
echo "=============== TESTS RESULTS =============="
tput colors > /dev/null
if [ "$?" == "0" ]; then
    COLOR_RED=`tput setaf 1`
    COLOR_GREEN=`tput setaf 2`
    COLOR_RESET=`tput sgr0`
fi

for (( i = 0 ; i < ${#TEST_NAMES[@]} ; i++ )); do
    if [ "${TEST_RESULTS[$i]}" == "0" ]; then
        RESULT="${COLOR_GREEN}PASS${COLOR_RESET}"
    else
        RESULT="${COLOR_RED}FAIL${COLOR_RESET}"
    fi
    str="Test $i [${TEST_NAMES[$i]}] "
    size=${#str}
    ndots=$((40-size))
    printf "${str}"
    printf %${ndots}s | tr " " "."
    echo $RESULT
done
