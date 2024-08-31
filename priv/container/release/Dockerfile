############################################################################
# This Dockerfile can be used to prepare a Docker image that runs swm-core #
# with cloud gate in a release mode a production machine.                  #
############################################################################

FROM ubuntu:22.04

ARG PYTHON_VERSION=3.10
ARG PYTHON_VERSION_FULL=3.10.14
ARG SWM_VERSION=$SWM_VERSION
ARG SWM_GATE_PACKAGE

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get clean
RUN apt-get update
RUN apt-get update --fix-missing
RUN apt-get install openssl -y
RUN apt-get install openssh-client -y  # for host certificates
RUN apt-get install python3 -y  # for setup
RUN apt-get install rlwrap -y  # for swmctl during setup
RUN apt-get install vim less mc -y  # for debug
RUN apt-get install -y supervisor

# Install python version we currently require:
RUN apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev
RUN apt-get install -y libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev
RUN cd /tmp && \
    wget https://www.python.org/ftp/python/$PYTHON_VERSION_FULL/Python-$PYTHON_VERSION_FULL.tgz && \
    tar -xf Python-$PYTHON_VERSION_FULL.tgz && \
    cd Python-$PYTHON_VERSION_FULL && \
    ./configure --enable-optimizations && \
    make -j $(nproc) && \
    make altinstall && \
    ln -s /usr/local/bin/python$PYTHON_VERSION /usr/local/bin/python && \
    ln -s /usr/local/bin/pip$PYTHON_VERSION /usr/local/bin/pip

RUN mkdir -p /opt/swm/spool

COPY $SWM_GATE_PACKAGE /opt/swm/
RUN pip install /opt/swm/$(basename "$SWM_GATE_PACKAGE")

COPY _build/packages/swm-$SWM_VERSION.tar.gz /opt/swm/swm.tar.gz
RUN tar zfx /opt/swm/swm.tar.gz -C /opt/swm/ && ln -s /opt/swm/$SWM_VERSION /opt/swm/current

# To run multiple processes in one container:
COPY priv/container/release/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# swm-core to swm-core connection port:
EXPOSE 10001

# HTTP client to swm-core port:
EXPOSE 8443

VOLUME /opt/swm

CMD ["/usr/bin/supervisord"]
