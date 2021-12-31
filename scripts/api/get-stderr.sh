#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <JOBID>"
    exit 1
fi
JOB_ID=$1

CERT=~/.swm/cert.pem
KEY=~/.swm/key.pem
CA=~/.swm/spool/secure/cluster/ca-chain-cert.pem

PORT=8443
HOST=$(hostname -s)

REQUEST=GET
URL="https://${HOST}:${PORT}/user/job/$JOB_ID/stderr"

curl --request ${REQUEST}\
     --cacert ${CA}\
     --cert ${CERT}\
     --key ${KEY}\
     ${URL}
echo
