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

1. Build the development container image (once) and start a shell in it:

```bash
make build-debug-container
make cr
```

2. Ensure `/opt/swm` exists and is owned by your user. The debug container
   mounts the host `/opt` directory, and `scripts/swm.env` requires
   `/opt/swm` to exist before any swm command runs. All following commands
   are executed by the regular user who owns the sources.

```bash
sudo mkdir -p /opt/swm
sudo chown $USER:$USER /opt/swm
```

3. From the swm-core directory, build the project:

```bash
make gen
make format
make compile porter
make release
```

`make release` is required before the first bootstrap (step 4) so
`scripts/setup-skyport-dev.sh` can create the worker distribution archive.

4. Bootstrap spool, certificates, and base configuration (first time only):

```bash
./scripts/setup-skyport-dev.sh
```

This creates `/opt/swm/spool` with node certificates, Mnesia data, and
imported base config. Re-run it only when you need to reset the dev
environment.

5. Run swm-core:

```bash
make run-skyport                  # foreground
# or: scripts/run-in-shell.sh -x -b   # background
```

6. Verify the API is up:

```bash
scripts/swm-ping localhost 10001  # expect: Pong: idle
```

To run a cluster management node instead of the default Sky Port node:

```bash
scripts/run-in-shell.sh -c
```
