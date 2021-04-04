#!/usr/bin/env bash

set -o xtrace

ME=$(readlink -f "$0")
DIR=$( cd "$( dirname "$ME" )" && pwd )
export SWM_LIB=${DIR}/../../_build/default/lib/swm/ebin
echo "SWM_LIB=${SWM_LIB}"

# Re-run the script by user which username passed to arguments:
if [ "$UID" == "0" ]; then
  if [ $# != 1 ]; then
    echo "Wrong number of arguments!"
    echo "Usage:"
    echo "  $0 USERNAME"
    echo
    exit 1
  fi
  RUN_USER=$1
  runuser -u ${RUN_USER} $0 $@
  exit $?
else
  echo "Current user ID: $UID"
fi

cd ${DIR}
cp ./job.sh /tmp
chmod +x /tmp/job.sh

. /usr/erlang/activate
./run.escript -d
exit $?

