#!/bin/bash

JOB_SCRIPT_PATH=$(mktemp --suffix=.swm)
cat > ${JOB_SCRIPT_PATH} <<EOF
#!/bin/bash
# SWM relocatable
#SWM image ubuntu-18.04
# SWM flavor m1.small
date
hostname
EOF

CERT=~/.swm/cert.pem
KEY=~/.swm/key.pem
CA=/opt/swm/spool/secure/cluster/ca-chain-cert.pem

PORT=8443
HOST=$(hostname -s)

REQUEST=POST
HEADER="Accept: application/json"
URL="https://${HOST}:${PORT}/user/job?path=${JOB_SCRIPT_PATH}"

curl --request ${REQUEST}\
     --cacert ${CA}\
     --cert ${CERT}\
     --key ${KEY}\
     --header "${HEADER}"\
     ${URL}
echo
