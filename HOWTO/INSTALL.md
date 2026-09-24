Installation
============

Job containers (recommended: rootless Podman + crun)
----------------------------------------------------

Supported job execution uses **rootless Podman** with **crun** via the native
libpod API (unix socket). See HOWTO/CONTAINERS.md for architecture, versions,
GPU (NVIDIA CDI), and migration notes (ticket #7).

On each compute node:

1. Install Podman and crun; ensure cgroup v2 and subuid/subgid for the swm user.
2. Pin the OCI runtime:
   ```bash
   mkdir -p ~/.config/containers
   printf '[engine]\nruntime = "crun"\n' >> ~/.config/containers/containers.conf
   ```
3. Enable the API socket:
   ```bash
   systemctl --user enable --now podman.socket
   # typical path: $XDG_RUNTIME_DIR/podman/podman.sock
   ```
4. Configure SkyPort globals (defaults are already `podman` in `base.config`):
   - `execution_method` = `podman` (and/or `cont_type` = `podman`)
   - optional: `SWM_CONTAINER_PODMAN_SOCK` if the socket path is non-default
   - to keep the legacy Docker job path: set `execution_method` = `docker`

Verify the stack (no SkyPort required):

```bash
./scripts/ci-podman-smoke.sh
```

Legacy: Docker Engine for jobs
------------------------------

Docker Engine remains available as a **legacy** job backend (`execution_method=docker`
/ `cont_type=docker`) and is still used to deploy the SkyPort control plane
(e.g. `skyport-dev`). New deployments should prefer Podman for jobs.

If you still run jobs via Docker, the daemon must listen on TCP (default port
6000, global `cont_port`):

```bash
# add to docker.service: -H tcp://0.0.0.0:6000
systemctl daemon-reload && systemctl restart docker
```

When SkyPort itself runs inside a Docker container (e.g. `skyport-dev`) and uses
the **legacy Docker job path**, it talks to the host Docker API as hostname
`host` on port 6000. Ensure:

1. The container is started with `--add-host=host:host-gateway`
   (see `scripts/start-debug-container.sh`).
2. If UFW (or another host firewall) is active with a default DROP policy,
   allow Docker bridge traffic to port 6000, for example:
   `ufw allow in on <skyportnet-bridge> to any port 6000 proto tcp`
   Otherwise inspect/create calls fail and jobs report
   "Container image not found" even when `docker images` shows the image.

For Podman from `skyport-dev`, mount the host Podman socket and set
`SWM_CONTAINER_PODMAN_SOCK` (in-container Podman packages are experiments only).


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
