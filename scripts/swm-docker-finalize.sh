#!/bin/sh
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -x

LOG=/tmp/swm-docker-finalize.log
PROGRAM_NAME=$0

if [ $# -eq 5 ]; then

    USER_NAME=$1
    UID=$2
    GID=$3
    HOST_IP=$4
    WORK_DIR=$5

    echo >> $LOG
    date -u +"%Y-%m-%dT%H:%M:%SZ" >> $LOG

    GROUP_NAME=$(getent group $GID)
    if [ "$?" = "0" ]; then
        echo "Some group with gid=$GID and name ${GROUP_NAME} already exists => reuse it" >> $LOG
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
            usermod -l ${USER_NAME} ${OLD_USERNAME} 2>&1 >> $LOG
        fi
        echo "User ${USER_NAME} will be added to group with gid=$GID" >> $LOG
        usermod -g ${GROUP_NAME} ${USER_NAME} 2>&1 >> $LOG
    else
        echo "New user with UID=$UID will be added: ${USER_NAME}" >> $LOG
        useradd -g ${USER_NAME} -u $UID ${USER_NAME} 2>&1 >> $LOG
    fi
    if [ "$?" = "0" ]; then
        echo "User ${USER_NAME} with uid=$UID has been added" >> $LOG
    else
        echo "Could not add user ${USER_NAME} with uid=$UID" >> $LOG
        exit 2
    fi

    echo "Add host IP $HOST_IP to /etc/hosts into the container" >> $LOG
    echo >> /etc/hosts
    echo "$HOST_IP swm_server_host" >> /etc/hosts
    echo "New /etc/hosts:" >> $LOG
    cat /etc/hosts >> $LOG

    echo "Validate job work directory existence: ${WORK_DIR}" >> $LOG
    if [ -d ${WORK_DIR} ]; then
        echo "The job work directory already exists" >> $LOG
    else
        echo "Create the job work directory" >> $LOG
        mkdir -p ${WORK_DIR} 2>&1 > $LOG
    fi

    echo "Ensure ownership of the job work directory as ${UID}:${GID}" >> $LOG
    chown ${UID}:${GID} ${WORK_DIR} 2>&1 > $LOG

else
    MSG="Usage: ${PROGRAM_NAME} <USER_NAME> <UID> <GID> <HOST_IP> <WORK_DIR>"
    echo $MSG
    echo $MSG >> $LOG
    exit 3
fi

echo >> $LOG
date -u +"%Y-%m-%dT%H:%M:%SZ" >> $LOG
echo "Finalization completed" >> $LOG
exit 0
