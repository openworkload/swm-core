# Job containerization

How Sky Port runs user jobs inside containers.

## Overview

By default, jobs run under **rootless Podman** with **crun**:

```
swm (compute node)
  -> Podman native API (libpod, unix socket)
  -> crun
  -> job container (Porter as PID 1)
  -> Porter
  -> user job script
```

**Porter** always runs **inside** the job container. It never calls Podman, crun, or any OCI runtime.

## Who owns what

| Owner | Responsibility |
|-------|----------------|
| **swm on the compute node** | Allocation, cgroup budget, container lifecycle, logs, cancel/signals, cleanup |
| **OCI runtime (crun via Podman)** | Namespaces, mounts, rootfs, starting Porter |
| **Porter** | Drop privileges to the job user, run the script, stream `#process{}` status, report exit status |

## Job lifecycle

1. **Create and start** the container:
   - Main command in the container `swm-porter`;
   - Host networking (needed for multi-node MPI / future PMIx-style wireup);
   - Explicit bind mounts (`/home`, `/tmp`, `$SWM_ROOT`, workdir). Add extras
     with `SWM_CONTAINER_EXTRA_BINDS`.
2. **Finalize** (short exec of `swm-container-finalize.sh`): ensure `/etc/passwd`
   and `/etc/group` contain the job user (Porter needs `getpwnam`), fix workdir
   ownership, add a `swm_server_host` hosts entry.
3. **Attach** and send the Erlang job+user binary to Porter on stdin.
4. Porter starts the user script and streams process status.
5. On finish, cancel, or error: stop and **delete** the container; free the node allocation.

Images that define their own `ENTRYPOINT` must still allow overriding the
command to Porter (or clear the entrypoint).

## Finalize script

Default: `scripts/swm-container-finalize.sh` (override with `SWM_CONTAINER_FINALIZE`).

It appends passwd/group lines when missing, `chown`s the workdir, and updates
hosts -- no dependency on the `adduser` package. That matters for minimal
images such as stock `ubuntu:24.04`.

## Configuration

| Knob | Notes |
|------|-------|
| `execution_method` | `native` \| `container`. Default: **`container`** (Podman + crun) |
| `SWM_CONTAINER_PODMAN_SOCK` | Podman API socket (default `$XDG_RUNTIME_DIR/podman/podman.sock`) |
| `SWM_CONTAINER_REQUIRE_CRUN` | Default `1`: Podman path requires OCI runtime **crun** |
| `SWM_CONTAINER_*` | Env prefix for container settings (`SWM_FINALIZE_IN_CONTAINER` still accepted as alias) |
| `SWM_CONTAINER_FINALIZE` | Finalize script path |
| `SWM_CONTAINER_EXTRA_BINDS` | Extra binds: `src:dst[:ro],...` |
| Entrypoint | Empty by default (Porter is the container command / PID 1) |

On each compute node:

1. Install Podman and crun; ensure cgroup v2 and subuid/subgid for the swm user
2. Pin runtime: `runtime = "crun"` in `~/.config/containers/containers.conf`
3. Enable the API socket: `systemctl --user enable --now podman.socket`

Quick check (no Sky Port required):

```bash
./scripts/ci-podman-smoke.sh
```

Compute nodes install Podman+crun on the **host**.

## Compatibility (tested reference)

| Component | Notes | Tested |
|-----------|-------|--------|
| Linux | User namespaces + cgroup v2 for rootless | Ubuntu 24.04, kernel 6.8 |
| Podman | Rootless; libpod via `podman.socket` | 4.9.3 |
| crun | Required OCI runtime | 1.14.1 |
| conmon | Comes with Podman | 2.1.10 |
| Rootless IDs | `/etc/subuid` + `/etc/subgid` for the swm user | required |
| API socket | Typically `/run/user/$UID/podman/podman.sock` | `systemctl --user` |
| Job images | OCI/Docker images from registries | e.g. `ubuntu:24.04` |
| NVIDIA CDI | Required when the job asks for GPUs (see below) | validate on GPU hosts |

## GPU (NVIDIA CDI)

- GPUs use **NVIDIA CDI** only.
- If `#SWM gpus` > 0 and CDI is missing or unusable: **hard error** (no silent CPU-only run).
- Job details should explain the failure, for example:

  > GPU job requires NVIDIA CDI on the compute node, but CDI was not available

Host needs: NVIDIA driver, `nvidia-container-toolkit` with CDI generation
(e.g. `nvidia-cdi-refresh`), cgroup v2, and CDI specs under `/etc/cdi` or `/var/run/cdi`.
