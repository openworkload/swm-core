
Steps to deploy a development environment from scratch
======================================================

Dependencies:
------------

1. Erlang/OTP 24 (installed in the dev container automatically)
2. rlwrap (installed in the dev container automatically)
3. cog (https://pypi.python.org/pypi/cogapp) (installed in the dev container automatically)
4. swm-sched (should be cloned to swm parent directory)

Dependencies installation example (for Ubuntu):
----------------------------------------------

```console
pip install cogapp
install kerl from https://github.com/yrashk/kerl
sudo apt-get install libgtk-3-dev build-essential libncurses5-dev openssl libssl-dev fop xsltproc unixodbc-dev # for erlang distribution build
KERL_CONFIGURE_OPTIONS="--disable-hipe --enable-smp-support --enable-threads  --enable-kernel-poll --with-ssl"
kerl update releases
kerl build 24.2 24_2_SSL
mkdir -p /usr/erlang
kerl install 24_2_SSL /usr/erlang
. /usr/erlang/activate
```

How to build in container:
-------------------------

```console
make cb  # build a new container with erlang and other packages installed
make cr  # start the container and run bash in it
cd <swm-sched path>
make
cd <swm path>
make
exit
```

How to build SkyWM:
------------------

```console
git clone <repo>
cd swm
make
```

How to build a release package:
------------------------------

```console
make
make release
```

How to create worker archive using already created dev setup:
------------------------------------------------------------

```console
scripts/setup.linux -a -t
```
