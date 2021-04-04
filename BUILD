
Steps to deploy a development environment from scratch
======================================================

Dependencies:
------------

1. Erlang/OTP 22 (installed in the container automatically)
2. rlwrap (installed in the container automatically)
3. cog (https://pypi.python.org/pypi/cogapp) (installed in the container automatically)
4. swm-sched (should be cloned to directory that also contains swm directory)

Dependencies installation example (for Ubuntu):
----------------------------------------------

pip install cogapp
install kerl from https://github.com/yrashk/kerl
sudo apt-get install libgtk-3-dev build-essential libncurses5-dev openssl libssl-dev fop xsltproc unixodbc-dev # for erlang distribution build
KERL_CONFIGURE_OPTIONS="--disable-hipe --enable-smp-support --enable-threads  --enable-kernel-poll --with-ssl"
kerl update releases
kerl build 22.3 22_3_SSL
mkdir -p /usr/erlang
kerl install 22_3_SSL /usr/erlang
. /usr/erlang/activate

How to build in container:
-------------------------

make cb  # build a new container with erlang and other packages installed
make cr  # start the container and run bash in it
cd <swm-sched path>
make
cd <swm path>
make
exit

How to build SkyWM:
------------------

git clone <repo>
cd swm
make

How to build a release package:
------------------------------

make
make release
