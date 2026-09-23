# Job containerization (SkyPort)

This document describes how SkyPort runs **job containers**, the planned move from
Docker Engine to **rootless Podman + crun**, and the compatibility / latency
baseline captured in ticket
[#7](https://github.com/openworkload/swm-core/issues/7) Phase 0.

> **Control plane vs jobs:** SkyPort itself may still be deployed with Docker
> (for example `skyport-dev`). That is separate from the **job execution** path
> described here.

## Overview

Target job path:

```
swm (compute node)
  -> native Podman REST API (libpod, unix socket)
  -> crun
  -> job container (Porter as PID 1)
  -> Porter
  -> user job script
```

Historical job path (still current in product code until later phases):

```
swm -> Docker Engine API (often TCP :6000) -> container -> Porter -> user script
```

Porter stays **inside** the job container. Porter never calls Podman, crun, or an
OCI runtime.

Phase 0 spike scripts (not used by product code):

- `scripts/phase0-podman-spike.sh` — native libpod create/start/exec + Porter PID1
- `scripts/phase0-latency-baseline.sh` — Docker vs Podman timing
- `scripts/swm-container-finalize.sh` — redesigned minimal finalize (prototype)

## Ownership model

| Owner | Responsibility |
|-------|----------------|
| **swm on the compute node** | Allocation, cgroup budget for the job, container lifecycle, logs plumbing, signals/cancel, cleanup |
| **OCI runtime (crun via Podman)** | Namespaces, mounts, rootfs, starting Porter |
| **Porter** | User identity drop, script exec, `#process{}` status stream, exit status |

## Lifecycle (high level)

1. **Create + start** the job container:
   - Command = Porter (for example `swm-porter -d`)
   - **No** SWM-injected tini/catatonit — Porter is PID 1
   - Host networking (multi-node MPI / future PMIx wireup)
   - Explicit bind mounts (`/home`, `/tmp`, `$SWM_ROOT`, workdir) — **no** `VolumesFrom`
2. **Finalize** (fast, rootless-oriented): at most one short exec of
   `swm-container-finalize.sh` (or create-time equivalent later) so `/etc/passwd`
   and `/etc/group` contain the job user Porter will `getpwnam`, workdir is
   owned correctly, and a `swm_server_host` hosts entry exists.
3. **Attach / send** the Erlang job+user binary to Porter stdin.
4. Porter forks the user script and streams process status.
5. On finish / cancel / error: stop and delete the container; free node allocation.

## Compatibility matrix

Values below were validated on the Phase 0 spike host (2026-09-23). Marked
**required** vs **tested**.

| Component | Required / notes | Tested on |
|-----------|------------------|-----------|
| Linux | Modern kernel with user namespaces + cgroup v2 for rootless | Ubuntu 24.04, kernel 6.8.0-139-generic |
| Podman | Rootless; native libpod API via `podman system service` / `podman.socket` | **4.9.3** (API 4.9.3, MinAPI 4.0.0) |
| crun | Preferred OCI runtime (`containers.conf`: `runtime = "crun"`) | **1.14.1** |
| conmon | Pulled in with Podman | 2.1.10 |
| cgroup | **cgroup v2** for rootless resource control | v2 (`cpu`, `memory`, `pids`) |
| Rootless IDs | `/etc/subuid` + `/etc/subgid` for the swm compute user | `taras:100000:65536` |
| API transport | Unix socket (typical `/run/user/$UID/podman/podman.sock`) | Enabled via `systemctl --user enable --now podman.socket` |
| Job image format | OCI/Docker images from registries (unchanged) | `ubuntu:24.04` |
| NVIDIA CDI | **Required** when `#SWM gpus` > 0 (see GPU section) | Not present on Phase 0 host (no GPU) — validate on GPU node in Phase 2 |
| Docker Engine | Not required for the target job path | Still used for control plane / transitional job path |

### Init process

- SWM does **not** inject tini.
- Spike confirmed Porter as PID 1: host `/proc/<pid>/cmdline` = `/opt/swm-porter -d`.
- Images that define their own `ENTRYPOINT` must be compatible with overriding
  command to Porter, or operators must clear the entrypoint.

### Finalize redesign notes

Legacy `scripts/swm-docker-finalize.sh` uses `addgroup` / `useradd` / `usermod`
and requires the `adduser` package on Debian/Ubuntu images. Stock
`ubuntu:24.04` does **not** ship `addgroup` by default.

New `scripts/swm-container-finalize.sh`:

- Appends `/etc/passwd` and `/etc/group` lines when missing
- `chown` workdir; appends hosts entry
- No dependency on `adduser`
- Works under rootless mapped root (Phase 0 spike)

Product wiring of the new script happens in a later phase; Phase 0 proves it.

## Configuration (current + planned)

| Knob | Today (Docker jobs) | Target (Podman jobs) |
|------|---------------------|----------------------|
| Runtime API | Docker Engine HTTP (often `host:6000`) | Native Podman libpod on unix socket |
| OCI runtime | Docker’s default (often runc) | **crun** |
| Env prefix | `SWM_DOCKER_*` | Prefer `SWM_CONTAINER_*` (keep aliases during transition) |
| Finalize | `SWM_FINALIZE_IN_CONTAINER` → `swm-docker-finalize.sh` | `swm-container-finalize.sh` |
| Entrypoint | Often tini via `SWM_DOCKER_ENTRYPOINT` | Empty / image default; Porter is Cmd |
| VolumesFrom | `SWM_DOCKER_VOLUMES_FROM` | Explicit binds only |
| GPU | Docker `DeviceRequests` / nvidia | **NVIDIA CDI** only |

Debug container (`priv/container/debug/Dockerfile`) installs `podman` + `crun`
for **local experiments only**. SkyPort product code must not use in-container
Podman as the supported job runtime. Release images are unchanged for this
ticket. Real compute nodes install Podman+crun on the **host**.

## Why not Docker Engine for HPC job containers

Docker Engine is a poor fit for short HPC tasks and site security models:

- Privileged daemon / socket culture vs rootless Podman
- Extra start hops (create, attach, start, exec finalize, attach again)
- Heavier finalize (`useradd` tools) and historical tini entrypoint
- Fixed Porter sleep (~2s) waiting on finalize races (to be removed once finalize is deterministic)
- crun is typically faster to spawn than runc for many create/exec workloads

### Latency baseline (Phase 0)

Measured 2026-09-23 on the spike host (2 vCPU). Method:
`scripts/phase0-latency-baseline.sh` with image `swm-phase0-ubuntu:24.04`
(ubuntu:24.04 + `adduser` so the **legacy** finalize can succeed for a fair
comparison). Averages over **3** warm rounds. Microbenchmark of create / start /
finalize / trivial follow-up exec — **not** a full SkyPort submit (no Porter EI
attach, no scheduler).

Raw JSON: captured as `/tmp/phase0-latency.json` during Phase 0; numbers below
are the published baseline.

| Stage | Docker (legacy finalize) | Podman native API + minimal finalize |
|-------|-------------------------:|-------------------------------------:|
| A. create | 232 ms | 142 ms |
| B. start | 387 ms | 156 ms |
| C. finalize exec | 389 ms (`swm-docker-finalize.sh`) | 233 ms (`swm-container-finalize.sh`) |
| E. create → first trivial command | **1152 ms** | **745 ms** |
| Finalize-only (docker exec, same host) | 434 ms | **171 ms** |

Additional SWM-imposed delay on the real path today: Porter waits about **2 s**
before reading stdin (`CHILD_WAITING_TIME` / sleep in `porter.cpp`) to race
finalize. That dominates short jobs and should drop once finalize completion is
deterministic.

**Interpretation:** Even before removing Porter’s sleep, Podman+crun+minimal
finalize already cuts the measured create→ready tax by roughly **35%** on this
host. Docker Engine is not the HPC-oriented job runtime going forward.

Re-run:

```bash
systemctl --user start podman.socket
./scripts/phase0-latency-baseline.sh --json /tmp/phase0-latency.json
```

## GPU (NVIDIA CDI)

Locked policy for the Podman job path:

- Rootless Podman + **NVIDIA CDI** only (no Docker `DeviceRequests` fallback).
- When a job requests GPUs (`#SWM gpus` &gt; 0) and CDI is missing or unusable:
  **hard error** — do not run as CPU-only.
- Put a clear message in the job **details** string (`state_details`), for example:

  > GPU job requires NVIDIA CDI on the compute node, but CDI was not available

Host expectations (to validate on a GPU node in Phase 2):

- NVIDIA driver
- `nvidia-container-toolkit` with CDI generation (for example `nvidia-cdi-refresh`)
- cgroup v2 + rootless device access via CDI specs under `/etc/cdi` or `/var/run/cdi`

Phase 0 host had **no** NVIDIA GPU / CDI — policy is documented; hardware
sign-off is a Phase 2 gate.

## PMIx / future parallel launch (invariants only)

Ticket #7 does **not** implement PMIx. Keep these invariants so a follow-up is
not a rewrite:

- Host networking remains the default
- Container create/start stays cheap enough for multi-process futures
- swm owns the job cgroup budget; containers inherit
- Allocation metadata reaches the workload via Porter (`SWM_*`)
- Porter remains inside the job container

## Dev notes

- Spike: `./scripts/phase0-podman-spike.sh` (needs `podman.socket`, crun, porter binary).
- `VolumesFrom` (for example `skyport-dev:ro`) must become explicit binds when
  the product path moves to Podman.
- In-container podman in `skyport-dev` is experimental only after rebuilding the
  debug image.
