#!/bin/bash

JOB_SCRIPT_BODY=$(cat <<-EOF
#!/bin/bash
#SWM image ubuntu:18.04
# SWM relocatable
# SWM flavor m1.small
date
hostname
sleep 100000
EOF
)

CERT=~/.swm/cert.pem
KEY=~/.swm/key.pem
CA=~/.swm/spool/secure/cluster/ca-chain-cert.pem

PORT=8443
HOST=$(hostname -s)

REQUEST=POST
URL="https://${HOST}:${PORT}/user/job"

curl --request ${REQUEST}\
     --cacert ${CA}\
     --cert ${CERT}\
     --key ${KEY}\
     --data "${JOB_SCRIPT_BODY}" \
     ${URL}
echo
