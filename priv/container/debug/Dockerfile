#######################################################################
# This Dockerfile can be used to prepare a Docker image that contains #
# everything required for Sky Port development (including Erlang).    #
# Example:                                                            #
# cd ~/projects/swm-core/priv/build                                   #
# docker build -t skyport-dev:24.3 .                                  #
# cd ~/projects/swm-core                                              #
# docker run -v `pwd`:/tmp/swm -ti skyport-dev:27.3 \                 #
#  /bin/bash -c "make && make release"                                #
#######################################################################

FROM ubuntu:22.04

ARG PYTHON_VERSION=3.10
ARG PYTHON_VERSION_FULL=3.10.17

ARG GTEST_VER=1.15.x
ARG LIBCLOUD_VER=3.1.0

ARG ERL_VER=27.3.3
ARG ERL_TAG=27_3_SSL

ENV KERL_VER=4.3.1
ENV KERL_CONFIGURE_OPTIONS="--without-odbc\
                            --disable-hipe\
                            --enable-smp-support\
                            --enable-threads\
                            --enable-kernel-poll\
                            --with-ssl"

ENV DEBIAN_FRONTEND=noninteractive

# Base linux packages
RUN apt-get clean
RUN apt-get update
RUN apt-get update --fix-missing
RUN apt-get upgrade -y
RUN apt-get install apt-utils -y
RUN apt-get install aptitude -y
RUN apt-get install git -y
RUN apt-get install rlwrap -y
RUN apt-get install vim -y
RUN apt-get install tmuxinator -y
RUN apt-get install sudo -y
RUN apt-get install mc -y
RUN apt-get install gcc -y
RUN apt-get install build-essential -y
RUN apt-get install libncurses5-dev -y
RUN apt-get install libssl-dev -y

# Python
RUN apt-get install zlib1g-dev -y
RUN apt-get install libgdbm-dev -y
RUN apt-get install libnss3-dev -y
RUN apt-get install libreadline-dev -y
RUN apt-get install libffi-dev -y
RUN apt-get install libsqlite3-dev -y
RUN apt-get install wget -y
RUN apt-get install libbz2-dev -y
RUN cd /tmp && \
    wget https://www.python.org/ftp/python/$PYTHON_VERSION_FULL/Python-$PYTHON_VERSION_FULL.tgz && \
    tar -xf Python-$PYTHON_VERSION_FULL.tgz && \
    cd Python-$PYTHON_VERSION_FULL && \
    ./configure --enable-optimizations && \
    make -j $(nproc) && \
    make altinstall
RUN ln -s /usr/local/lib/python$PYTHON_VERSION /usr/local/lib/python
RUN update-alternatives --install /usr/local/bin/python3 python3 /usr/local/bin/python${PYTHON_VERSION} 1
RUN update-alternatives --config python3 --skip-auto

# For JupyterHub
RUN apt-get install nodejs -y
RUN apt-get install npm -y
RUN npm install -g configurable-http-proxy

# For Erlang Runtime compilation
RUN apt-get install autoconf -y
RUN apt-get install openssl -y
RUN apt-get install fop -y
RUN apt-get install xsltproc -y

# Development and debugging tools
RUN apt-get install curl -y
RUN apt-get install openssh-server -y
RUN apt-get install gdb -y
RUN apt-get install gdbserver -y
RUN apt-get install htop -y
RUN apt-get install net-tools -y
RUN apt-get install iputils-ping -y
RUN apt-get install telnet -y
RUN apt-get install cmake -y
RUN apt-get install gnuplot -y
RUN apt-get install strace -y

# For documentation build
RUN apt-get install texlive-full -y
RUN apt-get install libxml2-utils -y

# For building Erlang/OTP with wxWidgets
RUN apt-get install libwxgtk3.0-gtk3-dev -y
RUN apt-get install libwxgtk-webview3.0-gtk3-dev -y
RUN apt-get install libgl1-mesa-dev -y
RUN apt-get install libglu1-mesa-dev -y
RUN apt-get install libpng16* -y

# For cogapp
RUN apt-get install python3-pip -y
RUN python${PYTHON_VERSION} -m pip install --upgrade pip
RUN pip3 install --upgrade pip
RUN pip3 install --upgrade setuptools
RUN pip3 install cogapp

# For OpenStack cloud gate
RUN pip3 install "apache-libcloud==${LIBCLOUD_VER}"

# Generic python tools for all python code
RUN pip3 install pip-tools
RUN pip3 install virtualenv

# For python package swmclient
RUN pip3 install openapi-python-client

# For using docker inside docker container
RUN apt-get install docker.io -y

# Build and install Erlang/OTP
WORKDIR /tmp/kerl/
RUN curl -O https://raw.githubusercontent.com/kerl/kerl/${KERL_VER}/kerl
RUN chmod +x kerl
RUN ./kerl build ${ERL_VER} ${ERL_TAG}
RUN mkdir -p /usr/erlang
RUN ./kerl install ${ERL_TAG} /usr/erlang

# Add additional files and settings into the container image
RUN echo . /usr/erlang/activate >> /etc/bash.bashrc
RUN mkdir /tmp/swm-sched
RUN mkdir /var/run/swm
COPY ./priv/container/debug/build-package.sh /var/run/swm/
COPY ./scripts/swm-docker-finalize.sh /var/run/swm/

# Build and install Google Tests
WORKDIR /tmp
RUN git clone --single-branch --branch v${GTEST_VER} https://github.com/google/googletest &&\
    cd googletest &&\
    cmake . -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX=/usr/local/GTest &&\
    make &&\
    make install

WORKDIR /tmp/swm
