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


Install Sky Port in production environment
-------------------------------------------

1 Unpack a content of swm archive into /opt/ directory:
```bash
$ mkdir /opt/swm
$ cp swm-$SWM_VERSION.tar.gz /opt/swm/
$ tar -xvzf /opt/swm/swm-$SWM_VERSION.tar.gz -C /opt/swm
```
2. Run setup procedure:
```bash   
$ /opt/swm/$SWM_VERSION/scripts/setup-swm-core.py -v $SWM_VERSION -p /opt/swm -s /opt/swm/spool -c  /opt/swm/$SWM_VERSION/priv/setup/setup.config -d grid
```

Install Sky Port in development environment
--------------------------------------------

1. Run container (using "make cr") and make sure /opt/swm
   exists and owned by the contanier user. All commands are
   executed by the regular user who owns the sources.

2. Go to swm-core directory and compile the project:

```bash
$ make compile
```

3. Setup:
```bash
$ ./scripts/setup-skyport-dev.linux
```
4. Test the setup (in the container):
```bash
$ scripts/run-in-shell.sh -c
[...]
```
