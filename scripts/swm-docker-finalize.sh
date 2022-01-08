#!/bin/sh

set -x

LOG=/tmp/swm-docker-finalize.log
PROGRAM_NAME=$0

if [ $# -eq 4 ]; then

    USER_NAME=$1
    UID=$2
    GID=$3
    SWM_SERVER_IP=$4

    echo >> $LOG
    date -u +"%Y-%m-%dT%H:%M:%SZ" >> $LOG

    GROUP_NAME=$(getent group $GID)
    if [ "$?" = "0" ]; then
        echo "Some group with gid=$GID and name ${GROUP_NAME} already exists => leave it" >> $LOG
    else
        GROUP_NAME=${USER_NAME}
        echo "New group ${GROUP_NAME} will be added with gid=${GID}" >> $LOG
        addgroup --gid $GID ${GROUP_NAME} 2>&1 >> $LOG
        if [ "$?" = "0" ]; then
            echo "Group ${GROUP_NAME} with gid=$GID has been added" >> $LOG
        else
            echo "Could not add group ${GROUP_NAME} with gid=$GID" >> $LOG
        fi
    fi

    OLD_USERNAME=$(id -nu ${UID})
    if [ "$?" = "0" ]; then
        if [ "${OLD_USERNAME}" = "${USER_NAME}" ]; then
            echo "User ${USER_NAME} with this uid already exists" >> $LOG
        else
            echo "Some user with this uid already exists => rename to the job's user" >> $LOG
            usermod -l ${USER_NAME} ${OLD_USERNAME}
        fi
        echo "User ${USER_NAME} will be added to group with gid=$GID" >> $LOG
        usermod -a -G ${GROUP_NAME} ${USER_NAME}
    else
        echo "New user will be added: ${USER_NAME}" >> $LOG
        adduser --uid $UID\
                --gid $GID\
                --no-create-home\
                --home=/home/${USER_NAME}\
                --disabled-password\
                ${USER_NAME} 2>&1 >> $LOG
    fi
    if [ "$?" = "0" ]; then
        echo "User ${USER_NAME} with uid=$UID has been added" >> $LOG
    else
        echo "Could not add user ${USER_NAME} with uid=$UID" >> $LOG
        exit 2
    fi

    echo "Add SWM server IP $SWM_SERVER_IP to /etc/hosts"
    echo >> /etc/hosts
    echo "$SWM_SERVER_IP swm_server_host" >> /etc/hosts

else
    MSG="Usage: ${PROGRAM_NAME} USER_NAME UID GID"
    echo $MSG
    echo $MSG >> $LOG
    exit 3
fi

exit 0
