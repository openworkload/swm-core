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
| **swm on the compute node** | Allocation, cgroup budget, container lifecycle, logs, cancel/signals, cleanup, PMIx server (`wm_pmix` / `swm-pmix`) |
| **OCI runtime (crun via Podman)** | Namespaces, mounts, rootfs, starting Porter; inherits SWM cgroup limits |
| **Porter** | Drop privileges to the job user, run the script, stream `#process{}` status, relay `swm-task` control to SWM, report exit status |
| **swm-task** | User-facing task launcher inside the job script (see `HOWTO/JOBS.md`) |

## Job lifecycle

1. **Create and start** the container:
   - Main command in the container `swm-porter`;
   - Host networking (needed for multi-node MPI / future PMIx-style wireup);
   - Explicit bind mounts (`/home`, `/tmp`, `/opt`, `$SWM_ROOT`, workdir). Add extras
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
| `SWM_CONTAINER_MEMORY_LIMIT` | Optional memory limit in bytes for the job cgroup (Podman `resource_limits`) |
| `SWM_CONTAINER_CPU_QUOTA` | Optional CPU quota (period 100000) for the job cgroup |
| Entrypoint | Empty by default (Porter is the container command / PID 1) |

## PMIx / multi-process tasks

Multi-node tasks use **`swm-task`** (optionally **`--pmix`** for MPI; not PRRTE). Flow:

1. Main node runs the job script in one Porter container (unchanged).
2. `swm-task ./app` talks to Porter via `SWM_PORTER_CTRL` (only Porter talks to SWM).
3. `wm_pmix` creates **one Porter container per allocated node** (v1: one rank per node).
4. With `--pmix`, `wm_pmix` also starts per-node **`swm-pmix`** and injects `PMIX_*` / `SWM_*`.
5. Cancel tears down rank containers (and stops `swm-pmix` if used).

See `HOWTO/JOBS.md` (Tasks section).

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

## InfiniBand / RDMA

When the compute host supports IB/RDMA, Sky Port automatically attaches it to
job containers (no `#SWM` flag). Host networking and the `/opt` bind (when
`/opt` exists on the host) are already used; jobscripts should set `PATH` /
`LD_LIBRARY_PATH` for HPC-X or Open MPI under `/opt` themselves.

Auto-attach when either:

- An RDMA/IB CDI spec is present under CDI dirs (`/etc/cdi`, `/var/run/cdi`, or
  `SWM_CONTAINER_CDI_PATHS`), or
- `/dev/infiniband` contains device nodes

Then create JSON includes:

| Field | Behavior |
|-------|----------|
| `cdi_devices` | RDMA names (default `rdma.com/ib=all`, or `SWM_CONTAINER_RDMA_CDI` comma list), merged with GPU CDI when `#SWM gpus` > 0 |
| `devices` | Fallback: each `/dev/infiniband/*` node if no RDMA CDI names |
| `cap_add` | `IPC_LOCK` (for RDMA memory registration) |
| `r_limits` | `MEMLOCK` soft+hard from the SWM process `/proc/self/limits` (unlimited encoded as uint64 max). Libpod field name is `r_limits`; rootless cannot raise memlock above the host user limit. |

Unlike GPUs, missing IB is **soft**: containers still start without IB fields.

### Host prep

1. Install OFED / rdma-core so `/dev/infiniband` exists on IB VMs.
2. Prefer an RDMA CDI spec (example under `/etc/cdi/rdma.com-ib.json`):

```json
{
  "cdiVersion": "0.5.0",
  "kind": "rdma.com/ib",
  "devices": [
    {
      "name": "all",
      "containerEdits": {
        "deviceNodes": [
          { "path": "/dev/infiniband/uverbs0", "type": "c", "major": 231, "minor": 192 }
        ]
      }
    }
  ]
}
```

(Adjust major/minor from `ls -l /dev/infiniband`.) Override device names with
`SWM_CONTAINER_RDMA_CDI=rdma.com/ib=all`.

3. Rootless Podman must be allowed to use those devices (CDI is the preferred
   path; plain `--device` may be limited under user namespaces).

### Examples and CI

- Azure NCCL over IB+GPU: `priv/examples/jobscripts/nccl-azure.sh`
- GHA fake GPU/IB validation: `scripts/ci-podman-gpu-ib.sh` (job `podman_gpu_ib`)
