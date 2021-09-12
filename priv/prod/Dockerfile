#######################################################################
# This Dockerfile can be used to prepare a Docker image that runs swm #
# on a production machine.                                            #
#######################################################################

FROM ubuntu:18.04

RUN DEBIAN_FRONTEND=noninteractive apt-get clean
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get update --fix-missing
RUN DEBIAN_FRONTEND=noninteractive apt-get install openssl -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install openssh-client -y  # for host certificates
RUN DEBIAN_FRONTEND=noninteractive apt-get install python3 -y  # for setup
RUN DEBIAN_FRONTEND=noninteractive apt-get install rlwrap -y  # for swmctl during setup
RUN DEBIAN_FRONTEND=noninteractive apt-get install vim less mc -y  # for debug

ARG SWM_VERSION=$SWM_VERSION
RUN mkdir -p /opt/swm/$SWM_VERSION
RUN mkdir -p /opt/swm/spool

COPY _build/default/rel/swm/ /opt/swm/$SWM_VERSION/
RUN ln -s /opt/swm/$SWM_VERSION /opt/swm/current

EXPOSE 10001
EXPOSE 8443

VOLUME /opt/swm

CMD ["/opt/swm/current/scripts/run-swm-foreground.sh"]
