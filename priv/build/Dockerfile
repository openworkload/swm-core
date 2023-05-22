#######################################################################
# This Dockerfile can be used to prepare a Docker image that contains #
# everything required for SWM build (including Erlang).               #
# Example:                                                            #
# cd ~/projects/swm-core/priv/build                                   #
# docker build -t swm-build:24.2 .                                    #
# cd ~projects/swm-core                                               #
# docker run -v `pwd`:/tmp/swm -ti swm-build:24.2 \                   #
#  /bin/bash -c "make && make release"                                #
#######################################################################

FROM ubuntu:18.04

ENV ERL_VER="24.2"
ENV ERL_TAG="24_2_SSL"
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
RUN apt-get install sudo -y
RUN apt-get install mc -y
RUN apt-get install gcc-8 -y

# For python 3.9
RUN apt-get install software-properties-common -y
RUN add-apt-repository ppa:deadsnakes/ppa -y
RUN apt-get update
RUN apt-get install python3.9 -y
RUN apt-get install python3.9-distutils -y
RUN apt-get install python3-all-dev -y

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 2
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
RUN update-alternatives --config python3 --skip-auto

# For Erlang Runtime compilation
RUN apt-get install autoconf -y
RUN apt-get install build-essential -y
RUN apt-get install libncurses5-dev -y
RUN apt-get install openssl -y
RUN apt-get install libssl-dev -y
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
RUN apt-get install libwxgtk3.0-dev -y
RUN apt-get install libgl1-mesa-dev -y
RUN apt-get install libglu1-mesa-dev -y
RUN apt-get install libpng16* -y

# For cogapp
RUN apt-get install python3-pip -y
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
RUN apt-get install docker.io -y

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
#COPY ./c_src/porter/swm-porter /var/run/swm/
COPY ./scripts/swm-docker-finalize.sh /var/run/swm/

# Build and install Google Tests
WORKDIR /tmp
RUN git clone https://github.com/google/googletest &&\
 cd googletest &&\
 cmake . -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX=/usr/local/GTest &&\
 make &&\
 make install

# Install Anaconda (useful for jupyter related development)
RUN curl -O https://repo.anaconda.com/archive/Anaconda3-2023.03-Linux-x86_64.sh
RUN bash /tmp/Anaconda3-2023.03-Linux-x86_64.sh -b -p /usr/anaconda3

WORKDIR /tmp/swm
