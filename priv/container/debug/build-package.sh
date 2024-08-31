#!/bin/bash
#
# The script builds SWM in container with user privelegies
#

if [ $# != 2 ]; then
  echo "Wrong number of arguments!"
  echo "Usage:"
  echo "  $0 UID USERNAME"
  echo
  exit 1
fi
BUILD_UID=$1
BUILD_USER=$2

echo
echo "*************** adduser $BUILD_UID $BUILD_USER ***************"
adduser --system --uid $BUILD_UID --disabled-password $BUILD_USER;

. /usr/erlang/activate

echo
echo "*************** make ***************"
runuser -u $BUILD_USER make
if [ "$?" != "0" ]; then
  exit 1
fi

echo
echo "*************** make release ***************"
runuser -u $BUILD_USER make release
if [ "$?" != "0" ]; then
  exit 1
fi

exit 0
