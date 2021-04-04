#!/bin/sh

##############################################
# Finalize docker container                  #
# Usage:                                     #
#       swm-docker-finalize.sh USER UID GID  #
##############################################

LOG=/var/log/swm-docker-finalize.log

if [ $# -eq 3 ]; then
  USER=$1
  UID=$2
  GID=$3
  echo >>$LOG
  date +"%H-%M-%S-%N" >>$LOG
  addgroup --gid $GID\
           ${USER} 2>&1 >>$LOG
  adduser  --uid $UID\
           --gid $GID\
           --system\
           --no-create-home\
           --disabled-password\
           ${USER} 2>&1 >>$LOG
  date +"%H-%M-%S-%N" >>$LOG
else
  MSG="$0: wrong number of arguments!"
  echo $MSG
  echo $MSG >>$LOG
  exit 1
fi

echo "User ${USER} has been added"
exit 0

