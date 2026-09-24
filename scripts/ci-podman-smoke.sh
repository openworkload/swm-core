#!/usr/bin/env bash
# CI / local smoke: rootless Podman + crun libpod API (ticket #7 Phase 3).
# Does not start swm; verifies the supported job-runtime stack is usable.
#
# Usage:
#   ./scripts/ci-podman-smoke.sh
#
# Env:
#   PODMAN_SOCK   override socket (default: $XDG_RUNTIME_DIR/podman/podman.sock)
#   SPIKE_IMAGE   image to create (default: ubuntu:24.04)
#   PODMAN_NESTED=1  force cgroupfs + vfs (also auto-detected under Docker/act)

set -euo pipefail

SOCK="${PODMAN_SOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock}"
# Prefer v5; fall back for older Podman (e.g. 3.x/4.x) if needed.
API_CANDIDATES=("${PODMAN_API_BASE:-}" "http://d/v5.0.0/libpod" "http://d/v4.0.0/libpod" "http://d/v3.0.0/libpod")
IMAGE="${SPIKE_IMAGE:-docker.io/library/ubuntu:24.04}"
NAME="swm-ci-podman-smoke-$$"

log() { printf '[podman-smoke] %s\n' "$*"; }
die() { printf '[podman-smoke] ERROR: %s\n' "$*" >&2; exit 1; }

command -v podman >/dev/null || die "podman not installed"
command -v crun >/dev/null || die "crun not installed"
command -v curl >/dev/null || die "curl not installed"
command -v python3 >/dev/null || die "python3 not installed"

log "podman=$(podman --version)"
log "crun=$(crun --version | head -1)"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "${XDG_RUNTIME_DIR}/podman" ~/.config/containers 2>/dev/null || true

# Nested Podman (Docker/act CI): cgroupfs + vfs avoids common start failures.
NESTED=0
if [[ "${PODMAN_NESTED:-}" == "1" ]] || [[ -f /.dockerenv ]] || grep -qE '/docker|/lxc' /proc/1/cgroup 2>/dev/null; then
  NESTED=1
  log "nested runtime detected; using cgroupfs + vfs"
  cat > ~/.config/containers/containers.conf <<'EOF'
[engine]
runtime = "crun"
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF
  cat > ~/.config/containers/storage.conf <<'EOF'
[storage]
driver = "vfs"
EOF
else
  if [[ ! -f ~/.config/containers/containers.conf ]]; then
    printf '[engine]\nruntime = "crun"\n' > ~/.config/containers/containers.conf
  fi
fi

start_api() {
  systemctl --user enable --now podman.socket 2>/dev/null \
    || podman system service --time=0 "unix://$SOCK" &
  for _ in $(seq 1 30); do
    [[ -S "$SOCK" ]] && break
    sleep 0.5
  done
}

if [[ "$NESTED" -eq 1 ]]; then
  # Reload API after storage/cgroup config changes.
  if [[ -S "$SOCK" ]]; then
    log "restarting podman API to pick up nested config"
    pkill -f "podman system service" 2>/dev/null || true
    systemctl --user stop podman.socket 2>/dev/null || true
    rm -f "$SOCK" 2>/dev/null || true
    sleep 1
  fi
fi

if [[ ! -S "$SOCK" ]]; then
  log "starting podman API service"
  start_api
fi
[[ -S "$SOCK" ]] || die "Podman socket not found: $SOCK"

RUNTIME=$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || true)
log "oci runtime=$RUNTIME"
[[ "$RUNTIME" == "crun" ]] || die "expected OCI runtime crun, got: ${RUNTIME:-unknown}"

API=""
for cand in "${API_CANDIDATES[@]}"; do
  [[ -z "$cand" ]] && continue
  if curl -sS --unix-socket "$SOCK" "$cand/_ping" 2>/dev/null | grep -q OK; then
    API="$cand"
    break
  fi
done
[[ -n "$API" ]] || die "libpod _ping failed (tried ${API_CANDIDATES[*]})"
log "libpod _ping OK ($API)"

podman image exists "$IMAGE" 2>/dev/null || podman pull "$IMAGE" >/dev/null

BODY=$(NAME="$NAME" IMAGE="$IMAGE" python3 - <<'PY'
import json, os
print(json.dumps({
  "name": os.environ["NAME"],
  "image": os.environ["IMAGE"],
  "command": ["/bin/sh", "-c", "echo swm-podman-smoke-ok; sleep 5"],
  "entrypoint": [],
  "netns": {"nsmode": "host"},
}))
PY
)

CREATE_OUT=$(curl -sS --unix-socket "$SOCK" -H 'Content-Type: application/json' -d "$BODY" \
  "$API/containers/create")
CID=$(printf '%s' "$CREATE_OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Id"])')
log "created ${CID:0:12}"

cleanup() {
  curl -sS -o /dev/null -X DELETE --unix-socket "$SOCK" \
    "$API/containers/${CID}?force=true&v=true" || true
}
trap cleanup EXIT

START_OUT=$(mktemp)
START_CODE=$(curl -sS -o "$START_OUT" -w '%{http_code}' -X POST --unix-socket "$SOCK" \
  "$API/containers/${CID}/start" || true)
if [[ "$START_CODE" != "204" && "$START_CODE" != "200" ]]; then
  log "start HTTP $START_CODE body=$(head -c 500 "$START_OUT" || true)"
  podman inspect "$CID" --format '{{json .State}}' 2>/dev/null || true
  rm -f "$START_OUT"
  die "container start failed"
fi
rm -f "$START_OUT"

# Brief wait then confirm still addressable / then force-delete via trap
sleep 1
curl -sS --unix-socket "$SOCK" "$API/containers/${CID}/json" \
  | python3 -c 'import sys,json; s=json.load(sys.stdin)["State"]["Status"]; assert s in ("running","exited"), s'
log "inspect OK"

log "OK: rootless Podman + crun libpod smoke passed"
