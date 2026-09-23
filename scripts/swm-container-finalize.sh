#!/bin/sh
#
# SPDX-FileCopyrightText: © 2021 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Fast rootless-oriented container finalize for SkyPort job containers.
# Replaces the heavier useradd/addgroup/usermod flow in swm-docker-finalize.sh.
#
# Goals:
#   - Work when the container "root" is a rootless mapped UID
#   - Stay cheap on the job start path (file writes + chown; no package tools)
#   - Leave /etc/passwd + /etc/group entries Porter can resolve via getpwnam(3)
#
# Usage:
#   swm-container-finalize.sh <USER_NAME> <UID> <GID> <HOST_IP> <WORK_DIR>
#
# Phase 1: default finalize for Docker job path via wm_container_cfg.
# Legacy scripts/swm-docker-finalize.sh remains for reference/rollback.

set -eu

LOG=/tmp/swm-container-finalize.log
PROGRAM_NAME=$0

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

if [ "$#" -ne 5 ]; then
    MSG="Usage: ${PROGRAM_NAME} <USER_NAME> <UID> <GID> <HOST_IP> <WORK_DIR>"
    echo "$MSG"
    echo "$MSG" >> "$LOG"
    exit 3
fi

USER_NAME=$1
USER_UID=$2
USER_GID=$3
HOST_IP=$4
WORK_DIR=$5

{
    echo
    ts
    echo "Minimal finalize user=${USER_NAME} uid=${USER_UID} gid=${USER_GID} host=${HOST_IP} workdir=${WORK_DIR}"
} >> "$LOG"

# Group: ensure an entry exists for USER_GID (reuse name if present).
if getent group "${USER_GID}" >/dev/null 2>&1; then
    echo "Reuse existing group for gid=${USER_GID}" >> "$LOG"
else
    # Format: name:passwd:GID:user_list
    echo "${USER_NAME}:x:${USER_GID}:" >> /etc/group
    echo "Appended /etc/group entry ${USER_NAME}:x:${USER_GID}:" >> "$LOG"
fi

# User: ensure passwd entry for USER_UID / USER_NAME.
if getent passwd "${USER_UID}" >/dev/null 2>&1; then
    OLD_NAME=$(getent passwd "${USER_UID}" | awk -F: '{print $1}')
    if [ "${OLD_NAME}" = "${USER_NAME}" ]; then
        echo "User ${USER_NAME} (uid=${USER_UID}) already present" >> "$LOG"
    else
        # Rename in place without usermod(8).
        sed -i "s/^${OLD_NAME}:/${USER_NAME}:/" /etc/passwd
        echo "Renamed passwd entry ${OLD_NAME} -> ${USER_NAME} for uid=${USER_UID}" >> "$LOG"
    fi
elif getent passwd "${USER_NAME}" >/dev/null 2>&1; then
    echo "WARNING: username ${USER_NAME} exists with different uid; leaving as-is" >> "$LOG"
else
    # name:passwd:UID:GID:gecos:home:shell
    echo "${USER_NAME}:x:${USER_UID}:${USER_GID}:SkyPort job user:/tmp:/bin/sh" >> /etc/passwd
    echo "Appended /etc/passwd entry for ${USER_NAME}" >> "$LOG"
fi

if ! grep -q "swm_server_host" /etc/hosts 2>/dev/null; then
    echo >> /etc/hosts
    echo "${HOST_IP} swm_server_host" >> /etc/hosts
    echo "Added hosts entry ${HOST_IP} swm_server_host" >> "$LOG"
fi

if [ ! -d "${WORK_DIR}" ]; then
    mkdir -p "${WORK_DIR}"
    echo "Created workdir ${WORK_DIR}" >> "$LOG"
fi
chown "${USER_UID}:${USER_GID}" "${WORK_DIR}"
echo "chown ${USER_UID}:${USER_GID} ${WORK_DIR}" >> "$LOG"

# Quick verification for callers (also printed on exec attach stream).
getent passwd "${USER_NAME}" || getent passwd "${USER_UID}"
ls -ld "${WORK_DIR}"

{
    ts
    echo "Finalization completed"
} >> "$LOG"

echo "Finalization completed"
exit 0
