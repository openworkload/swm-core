#!/bin/bash

CERT=~/.swm/cert.pem
KEY=~/.swm/key.pem
CA=~/.swm/spool/secure/cluster/ca-chain-cert.pem

PORT=8443
HOST=$(hostname -s)

REQUEST=GET
URL="https://${HOST}:${PORT}/user/job"

curl --request ${REQUEST}\
     --cacert ${CA}\
     --cert ${CERT}\
     --key ${KEY}\
     ${URL}
echo
