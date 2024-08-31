#!/bin/bash
#
# The script should run in container with mounted spool directory
# If spool directory is empty then the script runs setup first
#

SPOOL=/opt/swm/spool

if [ -z "$(ls -A "$SPOOL")" ]; then
    echo "The directory '$SPOOL' is empty => initiate setup and exit"
    /opt/swm/current/scripts/setup-skyport.linux
    exit 0
fi

source /opt/swm/current/scripts/swm.env
/opt/swm/current/bin/swm foreground
