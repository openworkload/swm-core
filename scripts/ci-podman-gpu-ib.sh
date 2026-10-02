#!/usr/bin/env bash
# CI: fake NVIDIA + RDMA CDI, compile SWM, assert generate_create_json wires
# GPU+IB, then Podman-create a container with IPC_LOCK / memlock / IB device
# and validate inside the container.
#
# Usage:
#   ./scripts/ci-podman-gpu-ib.sh
#
# Env:
#   PODMAN_SOCK   override socket (default: $XDG_RUNTIME_DIR/podman/podman.sock)
#   SPIKE_IMAGE   image (default: ubuntu:24.04)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

SOCK="${PODMAN_SOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock}"
IMAGE="${SPIKE_IMAGE:-docker.io/library/ubuntu:24.04}"
NAME="swm-ci-gpu-ib-$$"
CDI_DIR="${TMPDIR:-/tmp}/swm-ci-cdi-$$"
FAKE_IB_DIR="${TMPDIR:-/tmp}/swm-ci-ibdev-$$"

log() { printf '[podman-gpu-ib] %s\n' "$*"; }
die() { printf '[podman-gpu-ib] ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  podman rm -f "${NAME}" 2>/dev/null || true
  rm -rf "${CDI_DIR}" "${FAKE_IB_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

command -v podman >/dev/null || die "podman not installed"
command -v python3 >/dev/null || die "python3 not installed"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "${XDG_RUNTIME_DIR}/podman" ~/.config/containers "${CDI_DIR}" "${FAKE_IB_DIR}"

# Nested-friendly Podman (act / Docker). Disable cgroups: nested runners often
# lack delegated controllers (e.g. crun "pids is not available").
NESTED=0
CGROUP_ARGS=()
if [[ "${PODMAN_NESTED:-}" == "1" ]] || [[ -f /.dockerenv ]] || grep -qE '/docker|/lxc' /proc/1/cgroup 2>/dev/null; then
  NESTED=1
  CGROUP_ARGS=(--cgroups=disabled)
  log "nested runtime; cgroupfs + vfs + cgroups=disabled"
  cat > ~/.config/containers/containers.conf <<'EOF'
[engine]
runtime = "crun"
cgroup_manager = "cgroupfs"
events_logger = "file"

[containers]
cgroups = "disabled"
EOF
  cat > ~/.config/containers/storage.conf <<'EOF'
[storage]
driver = "vfs"
EOF
fi

if [[ "$NESTED" -eq 1 && -S "${SOCK}" ]]; then
  log "restarting podman API to pick up nested config"
  pkill -f "podman system service" 2>/dev/null || true
  systemctl --user stop podman.socket 2>/dev/null || true
  rm -f "${SOCK}" 2>/dev/null || true
  sleep 1
fi

if [[ ! -S "${SOCK}" ]]; then
  log "starting podman API"
  podman system service --time=0 "unix://${SOCK}" &
  for _ in $(seq 1 30); do
    [[ -S "${SOCK}" ]] && break
    sleep 0.5
  done
fi
[[ -S "${SOCK}" ]] || die "Podman socket missing: ${SOCK}"

# --- Fake CDI specs (filenames drive wm_container_cfg detection) ---
cat > "${CDI_DIR}/nvidia.com-gpu.json" <<'EOF'
{
  "cdiVersion": "0.5.0",
  "kind": "nvidia.com/gpu",
  "devices": [{ "name": "all", "containerEdits": {} }]
}
EOF
cat > "${CDI_DIR}/rdma.com-ib.json" <<EOF
{
  "cdiVersion": "0.5.0",
  "kind": "rdma.com/ib",
  "devices": [{
    "name": "all",
    "containerEdits": {
      "deviceNodes": [{
        "path": "${FAKE_IB_DIR}/uverbs0",
        "type": "c",
        "major": 1,
        "minor": 3
      }]
    }
  }]
}
EOF
# Char device under a temp dir for Podman --device. Eunit isolates from host
# /dev/infiniband via SWM_CONTAINER_IB_DEV_DIR in wm_podman_ib_tests.
if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
  SUDO=sudo
else
  SUDO=
fi
# Prefer mknod so Podman accepts --device; fall back to a regular file bind.
if $SUDO mknod "${FAKE_IB_DIR}/uverbs0" c 1 3 2>/dev/null; then
  $SUDO chmod 666 "${FAKE_IB_DIR}/uverbs0" 2>/dev/null || true
else
  touch "${FAKE_IB_DIR}/uverbs0"
fi

export SWM_ROOT="${SWM_ROOT:-/tmp}"

log "compile + eunit (cfg + create JSON)"
if [[ -x ./rebar3 ]]; then
  ./rebar3 compile
  # Comma-separated: multiple --module= flags only run the first module.
  ./rebar3 eunit --module=wm_container_cfg_tests,wm_podman_ib_tests
else
  die "rebar3 not found; run from repo with OTP available"
fi

log "assert generate_create_json (fake CDI env; no host /dev/infiniband required)"
export SWM_CONTAINER_CDI_PATHS="${CDI_DIR}"
export SWM_CONTAINER_RDMA_CDI="rdma.com/ib=all"
erl -noshell -pa _build/default/lib/*/ebin -eval '
  true = os:putenv("SWM_CONTAINER_CDI_PATHS", "'"${CDI_DIR}"'"),
  true = os:putenv("SWM_CONTAINER_RDMA_CDI", "rdma.com/ib=all"),
  true = os:putenv("SWM_ROOT", "/tmp"),
  ContImg = wm_entity:set([{name, "container-image"}, {count, 1},
                           {properties, [{value, "ubuntu:24.04"}]}], wm_entity:new(resource)),
  Gpus = wm_entity:set([{name, "gpus"}, {count, 1}, {properties, []}], wm_entity:new(resource)),
  Job = wm_entity:set([{id, "ci-gpu-ib"}, {container, "ci-gpu-ib"},
                       {request, [ContImg, Gpus]}, {env, []}], wm_entity:new(job)),
  Bin = wm_podman:generate_create_json(Job, "/bin/true", "ci-gpu-ib"),
  Map = wm_json:decode(Bin),
  Cdi = maps:get(<<"cdi_devices">>, Map),
  Names = [maps:get(<<"Name">>, D) || D <- Cdi],
  true = lists:member(<<"nvidia.com/gpu=all">>, Names),
  true = lists:member(<<"rdma.com/ib=all">>, Names),
  [<<"IPC_LOCK">>] = maps:get(<<"cap_add">>, Map),
  true = lists:any(fun(R) -> maps:get(<<"type">>, R) =:= <<"MEMLOCK">> end,
                   maps:get(<<"r_limits">>, Map)),
  file:write_file("/tmp/swm-ci-create.json", Bin),
  halt(0).
' || die "generate_create_json assertion failed"

log "Podman create with IB device + IPC_LOCK + memlock (runtime check)"
# CDI may be incomplete on CI; validate devices/caps/ulimits Podman applies.
podman pull -q "${IMAGE}" >/dev/null
IB_DEV="${FAKE_IB_DIR}/uverbs0"
# Use --device when the node is a char device; otherwise bind-mount the file.
if [[ -c "${IB_DEV}" ]]; then
  DEV_ARGS=(--device "${IB_DEV}:/dev/infiniband/uverbs0:rwm")
else
  DEV_ARGS=(-v "${IB_DEV}:/dev/infiniband/uverbs0:ro")
fi
podman create --name "${NAME}" \
  "${CGROUP_ARGS[@]}" \
  --cap-add IPC_LOCK \
  --ulimit memlock=-1:-1 \
  "${DEV_ARGS[@]}" \
  --network host \
  "${IMAGE}" \
  bash -lc 'set -e; test -e /dev/infiniband/uverbs0; ulimit -l; grep -q Cap /proc/self/status; echo GPU_IB_OK' \
  >/dev/null

if ! podman start -a "${NAME}" | tee /tmp/swm-ci-gpu-ib-out.txt; then
  die "podman start failed (see above); nested act often needs --cgroups=disabled"
fi
grep -q GPU_IB_OK /tmp/swm-ci-gpu-ib-out.txt || die "container did not report GPU_IB_OK"
INSPECT_CAPS="$(podman inspect -f '{{json .HostConfig.CapAdd}}' "${NAME}")"
echo "${INSPECT_CAPS}" | grep -q IPC_LOCK || die "CapAdd missing IPC_LOCK: ${INSPECT_CAPS}"

log "OK: create JSON has GPU+IB CDI/caps/memlock; container sees IB device + IPC_LOCK"
