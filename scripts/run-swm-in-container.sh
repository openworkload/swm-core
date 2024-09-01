#!/bin/bash
#
# The script should run in container with initialized spool directory
#

SPOOL=/opt/swm/spool

if [ -z "$(ls -A "$SPOOL")" ]; then
    echo "The directory '$SPOOL' is empty => exit"
    exit 1
fi

source /opt/swm/current/scripts/swm.env
/opt/swm/current/bin/swm foreground
