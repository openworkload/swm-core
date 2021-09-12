This directory contains files needed to prepare SWM for running on production machines
======================================================================================

Build container image with docker
---------------------------------

```console
scripts/build-prod-container.sh -v 0.2.0
```

Pull container image with dockerhub
---------------------------------

```console
TODO
```

Setup spool
-----------

When a fresh container image is pulled or built then it can be started with spool directory attached from the host. If spool is not initialized then setup-skyport.linux script must be executed inside
the container while spool directory is mounted there. This script initializes swm configuration and creates certificates. This script can be executed with the following commands (run on host).

```console
SWM_SPOOL_ON_HOST=$HOME/.swm/spool
mkdir -p ${SWM_SPOOL_ON_HOST}
COMMAND="/opt/swm/current/scripts/setup-skyport.linux -u $(id -u) -g $(id -g) -n $(id -u -n)"
docker run --rm -v $SWM_SPOOL_ON_HOST:/opt/swm/spool -v $HOME/.swm:/root/.swm --name=swm-core --hostname=$(hostname) --domainname=skyworkflows.com -ti swm-core:latest ${COMMAND}
```

In order to debug the setup script or swm daemon the following script will help (run on host):

```console
scripts/start-prod-container.sh -i -s
```

It runs bash in the container interactively and attachs script directory from the host. A second execution of the script will run bash in the same already running container.

Run swm daemon in container (in background)
-------------------------------------------

```console
SWM_SPOOL_ON_HOST=$HOME/.swm/spool
docker run --init --log-driver=syslog -d -p 10001:10001 -p 8443:8443 -v $SWM_SPOOL_ON_HOST:/opt/swm/spool -v $HOME/.swm:/root/.swm --name=swm-core --hostname=$(hostname) --domainname=skyworkflows.com swm-core:latest
```

After that the container can be controlled with:
```console
docker stop swm-core
docker start swm-core
```

Usefule links
-------------

* https://github.com/erlang/docker-erlang-example
