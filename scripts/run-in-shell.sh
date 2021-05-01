#!/usr/bin/env bash

while [[ $# -gt 0 ]]
do
i="$1"

case $i in
    -e|--etop|etop)
    ETOP=true
    shift # past argument
    ;;
    -o|--observer|observer)
    OBSERVER=true
    shift # past argument
    ;;
    -g|--grid)
    export SWM_SNAME=ghead
    shift # past argument
    ;;
    -c|--cluster)
    export SWM_SNAME=chead1
    shift # past argument
    ;;
    -x|--skyport)
    export SWM_SNAME=sp1
    shift # past argument
    ;;
    -b|--background)
    BACKGROUND=true
    shift # past argument
    ;;
    -s|--stop)
    STOP=true
    shift # past argument
    ;;
    -p|--ping)
    PING=true
    shift # past argument
    ;;
    -h|--help)
    echo "The script starts erlang shell attached to a new swm instance"
    echo "Usage: ${0##*/} [-e|-o] [-g|c]"
    echo "  -e|--etop|etop              run etop in remote shell"
    echo "  -o|--observer|observer      run observer in remote shell"
    echo "  -g|--grid                   run (or connect to) grid SWM instance"
    echo "  -c|--cluster                run (or connect to) cluster SWM instance"
    echo "  -b|--background             run SWM instance in background mode"
    echo "  -s|--stop                   stop SWM instance"
    echo "  -p|--ping                   ping SWM instance"
    exit 0
    ;;
    *)
    shift # past argument
    ;;
esac
done

ME=$( readlink -f "$0" )
ROOT_DIR=$( dirname "$( dirname "$ME" )" )

## Export variables
source ${ROOT_DIR}/scripts/swm.env

## Use paths in source directory
export SWM_CONTAINER_FINALIZE=${ROOT_DIR}/scripts/swm-docker-finalize.sh
export SWM_SCHED_EXEC=${ROOT_DIR}/../swm-sched/bin/swm-sched
export SWM_SCHED_LIB=${ROOT_DIR}/../swm-sched/bin

VM_ARGS=$(grep -v -E '^#|^-name|^-sname|^-args_file' "${SWM_VM_ARGS}" | xargs | sed -e 's/ / /g')

if [ $ETOP ]; then
  erl -name etop-`date +%s` ${VM_ARGS} -boot start_clean -remsh \'${SWM_SNAME}@$(hostname -f)\' \
    -s etop -output text -tracing off -sort msg_q -interval 1 -lines $( expr `tput lines` - 11 )
elif [ $OBSERVER ]; then
  erl -name observer-`date +%s` ${VM_ARGS} -boot start_clean -remsh \'${SWM_SNAME}@$(hostname -f)\' \
    -s observer
elif [ $STOP ]; then
  erl -name stop-`date +%s` ${VM_ARGS} -boot start_clean -noinput -noshell \
      -eval "io:format(\"~p~n\", [rpc:call('${SWM_SNAME}@$(hostname -f)', init, stop, [], 10000)]), halt(0)"
elif [ $PING ]; then
  erl -name ping-`date +%s` ${VM_ARGS} -boot start_clean -noinput -noshell \
      -eval "case {net_kernel:hidden_connect_node('${SWM_SNAME}@$(hostname -f)'), net_adm:ping('${SWM_SNAME}@$(hostname -f)')} of
               {true, pong} ->
                 timer:sleep(9000), %FIXME swm services are not always ready when pinged with net_adm:ping (use wm_pinger instead)
                 io:format(\"pong\n\", []),
                 halt(0);
               {_, pang} ->
                 io:format(\"Node ~p not responding to pings.\n\", ['${SWM_SNAME}@$(hostname -f)']),
                 halt(1)
             end"
elif [ $BACKGROUND ]; then
  erl -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_sasl -detached \
    -s swm -s sync
else
  erl -pa ${ROOT_DIR}/_build/default/lib/*/ebin -config ${SWM_SYS_CONFIG} -args_file ${SWM_VM_ARGS} -boot start_clean \
    -s swm -s sync
fi

