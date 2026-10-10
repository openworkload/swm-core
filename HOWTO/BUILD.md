# Build a development environment

This document shows how to build Sky Port from source.

## Dependencies

You need these tools:

1. Erlang/OTP 29 (the development container installs this for you)
2. cog ([cogapp](https://pypi.python.org/pypi/cogapp)) (the development container installs this for you)
3. swm-sched (clone this repository into the parent directory of swm-core)

## Install dependencies on Ubuntu

Use these commands if you do not use the development container:

```console
$ pip install cogapp
$ install kerl from https://github.com/kerl/kerl
$ sudo apt-get install libgtk-3-dev build-essential libncurses5-dev openssl libssl-dev fop xsltproc unixodbc-dev # for erlang distribution build
$ KERL_CONFIGURE_OPTIONS="--disable-hipe --enable-smp-support --enable-threads  --enable-kernel-poll --with-ssl"
$ kerl update releases
$ kerl build 29.1 29_1_SSL
$ mkdir -p /usr/erlang
$ kerl install 29_1_SSL /usr/erlang
$ . /usr/erlang/activate
```

## Build in a container

Do these steps:

```console
$ make cb  # build a new container with erlang and other packages installed
$ make cr  # start the container and run bash in it
$ cd <swm-sched path>
$ make
$ cd <swm path>
$ make
$ exit
```

## Build the Sky Port core daemon

Do these steps:

```console
$ git clone <repo>
$ cd swm
$ make
```

## Build a release package

Do these steps:

```console
$ make
$ make release
```

## Create a worker archive

Use this command when the development setup already exists:

```console
$ make worker
```

The archive includes public cluster CA trust files and node/host material. It
does not include the cluster CA private key (see [SECURITY.md](SECURITY.md)).
