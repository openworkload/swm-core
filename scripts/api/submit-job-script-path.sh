#!/bin/bash
# Client reads the script file; the server accepts only the request body
# (the old ?path= query parameter is rejected -- it read server-local files).

JOB_SCRIPT_PATH=$(mktemp --suffix=.swm)
cat > ${JOB_SCRIPT_PATH} <<EOF
#!/bin/bash
#SWM image ubuntu:24.04
# SWM relocatable
# SWM flavor m1.small
date
hostname
EOF

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
     --data-binary "@${JOB_SCRIPT_PATH}" \
     ${URL}
echo

rm -f "${JOB_SCRIPT_PATH}"
