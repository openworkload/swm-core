Installation
============

Prepare Docker (for both dev and prod setups)
----------------------------------------------

In the current version of SWM jobs are started via docker.
All the communications between SWM and docker daemon are performed
via a TCP port. By default it is port 6000 (set as SWM global option,
that can be changed). The developer or administrator should ensure
that the docker daemon listens to this port on the compute nodes
(usually by default it does not do that by default).

For that purpose this "-H tcp://0.0.0.0:6000" can be added to start
arguments in docker.service. This is a subject for improvement.

Then do "systemctl daemon-reload" and "systemctl restart docker".
This should be done on every compute node where the jobs are suppose to run.


To install production environment on Linux
-------------------------------------------

1 Unpack a content of swm archive into /opt/ directory:
```bash
$ mkdir /opt/swm
$ cp swm-$SWM_VERSION.tar.gz /opt/swm/
$ tar -xvzf /opt/swm/swm-$SWM_VERSION.tar.gz -C /opt/swm
```
2. Run setup procedure:
```bash   
$ /opt/swm/$SWM_VERSION/scripts/setup.linux -v $SWM_VERSION -p /opt/swm -s /opt/swm/spool -c  /opt/swm/$SWM_VERSION/priv/setup/setup-config.linux -d grid
```

To install development environment in Linux
--------------------------------------------

1. Run container (using "make cr") and make sure /opt/swm
   exists and owned by the contanier user. All commands are
   executed by the regular user who owns the sources.

2. Go to sources directory (e.g. $HOME/projects/swm) and setup
   grid and cluster management nodes into the container with
   the next command (no questions will be asked):
```bash
$ ./scripts/setup-dev.linux
```
3. Test the setup (in the container):
```bash
$ scripts/run-in-shell.sh -c
[...]
```
   In another terminal (after one more "make cr"):
```bash   
$ export SWM_API_PORT=10011
$ ./scripts/swmctl grid show
               | ALL       IDLE      DOWN      OFFLINE   BUSY
               --------------------------------------------------
      CLUSTERS | 0         0         0         0         0
    PARTITIONS | 0         0         0         0         0
         NODES | 1         1         0         0         0
               | ALL       QUEUED    RUNNING   ERROR     FINISHED
               --------------------------------------------------
          JOBS | 0         0         0         0         0

$ ./scripts/swmctl
[ts] grid
[ts > grid] show
               | ALL       IDLE      DOWN      OFFLINE   BUSY
               --------------------------------------------------
      CLUSTERS | 2         0         1         0         0
    PARTITIONS | 3         0         1         0         0
         NODES | 7         1         0         0         0
               | ALL       QUEUED    RUN       ERROR     COMPLETE
               --------------------------------------------------
          JOBS | 0         0         0         0         0
[ts > grid] sim start
Simulation has been started
[ts > grid] route node102 node304
ghead@ts
chead1@ts
phead1@ts
node102@ts
phead1@ts
phead3@ts
node304@ts
phead3@ts
phead1@ts
node102@ts
phead1@ts
chead1@ts
[ts > grid]
```
