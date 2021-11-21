#######################################################################
# This Dockerfile can be used to prepare a Docker image that contains #
# everything required for SWM build (including Erlang).               #
# Example:                                                            #
# cd ~/projects/swm-core/priv/build                                   #
# docker build -t swm-build:22.3 .                                    #
# cd ~projects/swm-core                                               #
# docker run -v `pwd`:/tmp/swm -ti swm-build:22.3 \                   #
#  /bin/bash -c "make && make release"                                #
#######################################################################

FROM ubuntu:18.04

ENV ERL_VER="22.3"
ENV ERL_TAG="22_3_SSL"
ENV KERL_CONFIGURE_OPTIONS="--without-odbc\
                            --disable-hipe\
                            --enable-smp-support\
                            --enable-threads\
                            --enable-kernel-poll\
                            --with-ssl"

# Base linux packages
RUN DEBIAN_FRONTEND=noninteractive apt-get clean
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get update --fix-missing
RUN DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install apt-utils -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install aptitude -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install git -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install rlwrap -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install vim -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install sudo -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install mc -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install gcc-8 -y

# For python 3.9
RUN DEBIAN_FRONTEND=noninteractive apt-get install software-properties-common -y
RUN DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:deadsnakes/ppa -y
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install python3.9 -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install python3.9-distutils -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install python3-all-dev -y

RUN DEBIAN_FRONTEND=noninteractive update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 2
RUN DEBIAN_FRONTEND=noninteractive update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
RUN DEBIAN_FRONTEND=noninteractive update-alternatives --config python3 --skip-auto

# For Erlang Runtime compilation
RUN DEBIAN_FRONTEND=noninteractive apt-get install autoconf -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install build-essential -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install libncurses5-dev -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install openssl -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install libssl-dev -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install fop -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install xsltproc -y

# Development and debugging tools
RUN DEBIAN_FRONTEND=noninteractive apt-get install curl -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install openssh-server -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install gdb -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install gdbserver -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install htop -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install net-tools -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install iputils-ping -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install telnet -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install cmake -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install gnuplot -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install strace -y

# For documentation build
RUN DEBIAN_FRONTEND=noninteractive apt-get install texlive-full -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install libxml2-utils -y

# For building Erlang/OTP with wxWidgets
RUN DEBIAN_FRONTEND=noninteractive apt-get install libwxgtk3.0-dev -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install libgl1-mesa-dev -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install libglu1-mesa-dev -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install libpng16* -y

# For cogapp
RUN DEBIAN_FRONTEND=noninteractive apt-get install python3-pip -y
RUN python3.9 -m pip install --upgrade pip
RUN pip3 install --upgrade pip
RUN pip3 install --upgrade setuptools
RUN pip3 install cogapp

# For pythonic gates and terminals
RUN pip3 install "apache-libcloud==3.1.0"

# Generic python tools for all python code
RUN pip3 install pip-tools
RUN pip3 install virtualenv

# For python package swmclient
RUN pip3 install openapi-python-client

# For using docker inside docker container
RUN DEBIAN_FRONTEND=noninteractive apt-get install docker.io -y

# Build and install Erlang/OTP
WORKDIR /tmp/kerl/
RUN curl -O https://raw.githubusercontent.com/kerl/kerl/1.8.0/kerl
RUN chmod +x kerl
RUN ./kerl build ${ERL_VER} ${ERL_TAG}
RUN mkdir -p /usr/erlang
RUN ./kerl install ${ERL_TAG} /usr/erlang

# Add additional files and settings into the container image
RUN echo . /usr/erlang/activate >> /etc/bash.bashrc
RUN mkdir /tmp/swm-sched
RUN mkdir /var/run/swm
COPY ./priv/build/build-package.sh /var/run/swm/
COPY ./c_src/porter/swm-porter /var/run/swm/
COPY ./scripts/swm-docker-finalize.sh /var/run/swm/

# Build and install Google Tests
WORKDIR /tmp
RUN git clone https://github.com/google/googletest &&\
    cd googletest &&\
    cmake . -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX=/usr/local/GTest &&\
    make &&\
    make install

WORKDIR /tmp/swm
