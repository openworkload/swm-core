# Installation

This document shows how to install Sky Port for jobs, production, and development.

## Job containers (recommended: rootless Podman + crun)

Sky Port runs jobs with **rootless Podman** and **crun**. It uses the native
libpod API on a Unix socket. See [CONTAINERS.md](CONTAINERS.md) for
architecture, versions, GPU (NVIDIA CDI), and migration notes (ticket #7).

On each compute node, do these steps:

1. Install Podman and crun. Make sure cgroup v2 is enabled. Make sure the swm
   user has subuid and subgid entries.
2. Set the OCI runtime to crun:
   ```bash
   mkdir -p ~/.config/containers
   printf '[engine]\nruntime = "crun"\n' >> ~/.config/containers/containers.conf
   ```
3. Start the API socket:
   ```bash
   systemctl --user enable --now podman.socket
   # typical path: $XDG_RUNTIME_DIR/podman/podman.sock
   ```
4. Set Sky Port globals (defaults in `base.config` already use `container`):
   - `execution_method` = `container`
   - optional: `SWM_CONTAINER_PODMAN_SOCK` if the socket path is not the default

Check the stack without Sky Port:

```bash
./scripts/ci-podman-smoke.sh
```

## Control plane and jobs

Docker (or Podman) deploys the Sky Port control plane (for example `skyport-dev`
via `make cr`). Job execution uses rootless Podman on the compute host. Job
execution does not use Docker Engine.

`make cr` / `scripts/start-debug-container.sh` mount the host Podman socket
(`$XDG_RUNTIME_DIR/podman/podman.sock`) into `skyport-dev` and set
`SWM_CONTAINER_PODMAN_SOCK`. Start the socket on the host first:

```bash
systemctl --user enable --now podman.socket
```

Podman packages inside the container are experiments only. Jobs use the host API.

## Install Sky Port in a production environment

1. Unpack the swm archive into `/opt/`:
```bash
$ mkdir /opt/swm
$ cp swm-$SWM_VERSION.tar.gz /opt/swm/
$ tar -xvzf /opt/swm/swm-$SWM_VERSION.tar.gz -C /opt/swm
```

2. Run the setup procedure:
```bash
$ /opt/swm/$SWM_VERSION/scripts/setup-swm-core.py -v $SWM_VERSION -p /opt/swm -s /opt/swm/spool -c  /opt/swm/$SWM_VERSION/priv/setup/setup.config -d grid
```

## Install Sky Port in a development environment

1. Build the development container image (one time). Then start a shell in it:

```bash
make build-debug-container
make cr
```

After `make cr`, the host user has passwordless `sudo` inside `skyport-dev`
(the container does not mount host `/etc/shadow`). Development uses pod
`skyport-dev-pod` with containers `skyport-dev` (core) and `skyport-dev-gate`
(gate under supervisord). The next `make cr` removes legacy non-pod containers
automatically.

2. Make sure `/opt/swm` exists and that your user owns it. The debug container
   mounts the host `/opt` directory. `scripts/swm.env` requires `/opt/swm`
   before any swm command runs. Run all later commands as the user who owns
   the sources.

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

`make release` is required before the first bootstrap (step 4). The setup
script `scripts/setup-skyport-dev.sh` needs the worker distribution archive.

4. Create spool, certificates, and base configuration (first time only):

```bash
./scripts/setup-skyport-dev.sh
```

This creates `/opt/swm/spool` with node certificates, Mnesia data, and
imported base config. Run it again only when you must reset the development
environment.

5. Start swm-core:

```bash
make run-skyport                  # foreground
# or: scripts/run-in-shell.sh -x -b   # background
```

6. Check that the API is up:

```bash
scripts/swm-ping localhost 10001  # expect: Pong: idle
```

To run a cluster management node instead of the default Sky Port node:

```bash
scripts/run-in-shell.sh -c
```
