#!/usr/bin/env bash


SWM_ROOT=/opt/swm
SIM_CONFIG="/tmp/swm/priv/setup/dev1.config"
TEST_JOB=/tmp/swm.job
FAILED=1
TOTAL_ATTEMPTS=24
WAIT_SECONDS=5


./test/prepare.sh -i ${SWM_ROOT} -s ${SIM_CONFIG}
if [ "$?" != "0" ]; then
    echo "ERROR: preparation for the test has failed"
    exit 1
fi

echo "
#!/usr/bin/env bash
#SWM name Test Job
#SWM workdir /tmp
echo \$SWM_JOB_ID
" > $TEST_JOB

echo
echo "Test Job:"
cat $TEST_JOB
echo


. /usr/erlang/activate

# Set environment for user commands:
export SWM_SNAME=chead1
export SWM_API_PORT=10011
source ${SWM_ROOT}/current/scripts/swm.env

SUBMIT_COMMAND="${SWM_JOB} submit $TEST_JOB"
echo "Run '$SUBMIT_COMMAND'"
JOB_ID=$(${SWM_JOB} submit $TEST_JOB)
echo "Submitted job ID: ${JOB_ID}"

for i in $(seq 1 $TOTAL_ATTEMPTS); do
    JOB_STATE=$(${SWM_JOB} show ${JOB_ID} | grep state -i | awk '{print $2}')
    echo "Submitted job state: ${JOB_STATE}"
    if [[ "${JOB_STATE}" == "\"F\"" ]]; then
        echo "Finished"
        FAILED=0
        break
    fi
    sleep $WAIT_SECONDS
done

if [[ "${FAILED}" == "1" ]]; then
    echo "Failed"
    #exit 1
fi

STDOUT_FILE=/tmp/${JOB_ID}.out
STDERR_FILE=/tmp/${JOB_ID}.err
echo
echo "Container hostname: '${HOSTNAME}'"
STDOUT=$(cat ${STDOUT_FILE} | tr -d '\n')
echo "Content of ${STDOUT_FILE}: '${STDOUT}'"
rm -f ${STDOUT_FILE} ${STDERR_FILE}
echo

if [[ "${STDOUT}" == "$JOB_ID" ]]; then
    exit 0
else
    exit 1
fi
