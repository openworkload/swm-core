#!/usr/bin/env bash
# Build and install Open MPI into /opt/openmpi with full PMIx support.
#
# Default: Open MPI 5.0.x with *bundled* PMIx + PRRTE + hwloc + libevent
# (--with-*=internal). That is the reliable way to get full PMIx integration
# on Ubuntu, where distro libpmix headers live under a multiarch path that
# Open MPI's configure often fails to use when given a bare --with-pmix=/usr.
#
# Usage:
#   sudo ./scripts/install-openmpi.sh
#   OPENMPI_VERSION=5.0.11 ./scripts/install-openmpi.sh
#   WITH_PMIX=external sudo -E ./scripts/install-openmpi.sh   # system libpmix-dev
#   WITH_PMIX=/usr/lib/x86_64-linux-gnu/pmix2 sudo -E ./scripts/install-openmpi.sh
#
# After install:
#   export PATH=/opt/openmpi/bin:$PATH
#   export LD_LIBRARY_PATH=/opt/openmpi/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
#
set -euo pipefail

PREFIX="${PREFIX:-/opt/openmpi}"
OPENMPI_VERSION="${OPENMPI_VERSION:-5.0.11}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/openmpi-build-$$}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
# internal (default) | external | auto | /absolute/pmix/prefix
WITH_PMIX="${WITH_PMIX:-internal}"
SKIP_APT="${SKIP_APT:-0}"

SRC_DIR="${BUILD_ROOT}/openmpi-${OPENMPI_VERSION}"
TARBALL="openmpi-${OPENMPI_VERSION}.tar.bz2"
DOWNLOAD_URL="https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/${TARBALL}"

# Log to stderr so command substitutions (e.g. resolve_support_flags) stay clean.
log() { printf '+ %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "root privileges required for: $*"
  fi
}

install_build_deps() {
  [[ "${SKIP_APT}" == "1" ]] && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get not found; skipping dependency install (set packages yourself)"
    return 0
  fi
  log "Installing build dependencies (apt)"
  run_as_root apt-get update -qq
  run_as_root apt-get install -y --no-install-recommends \
    build-essential \
    gfortran \
    wget \
    tar \
    ca-certificates \
    pkg-config \
    python3 \
    zlib1g-dev \
    libevent-dev \
    libhwloc-dev

  # Optional: only required when WITH_PMIX=external|auto uses the distro PMIx.
  if [[ "${WITH_PMIX}" != "internal" ]]; then
    log "Installing system PMIx devel packages"
    run_as_root apt-get install -y --no-install-recommends libpmix-dev libpmix-bin
    run_as_root apt-get install -y --no-install-recommends libpmix2t64 \
      || run_as_root apt-get install -y --no-install-recommends libpmix2 \
      || true
  fi
}

# Return absolute PMIx prefix if devel headers are present, else empty.
find_external_pmix_prefix() {
  local prefix=""
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists pmix 2>/dev/null; then
    prefix="$(pkg-config --variable=prefix pmix 2>/dev/null || true)"
  fi
  if [[ -n "${prefix}" && -f "${prefix}/include/pmix.h" ]]; then
    printf '%s\n' "${prefix}"
    return 0
  fi
  # Ubuntu multiarch layout when pkg-config is missing/misconfigured.
  local cand
  for cand in \
    /usr/lib/x86_64-linux-gnu/pmix2 \
    /usr/lib/aarch64-linux-gnu/pmix2 \
    /usr/local \
    /usr
  do
    if [[ -f "${cand}/include/pmix.h" ]]; then
      printf '%s\n' "${cand}"
      return 0
    fi
  done
  return 1
}

# Print configure args related to PMIx / PRRTE / hwloc / libevent (one per line).
resolve_support_flags() {
  local mode="${WITH_PMIX}"
  local pmix_prefix=""

  case "${mode}" in
    internal)
      log "Using Open MPI bundled PMIx/PRRTE/hwloc/libevent (recommended)"
      printf '%s\n' \
        --with-pmix=internal \
        --with-prrte=internal \
        --with-hwloc=internal \
        --with-libevent=internal
      return
      ;;
    external|auto)
      if pmix_prefix="$(find_external_pmix_prefix)"; then
        log "Using external PMIx at ${pmix_prefix}"
        # Distro PMIx was built against distro hwloc/libevent -- use those too.
        printf '%s\n' \
          "--with-pmix=${pmix_prefix}" \
          --with-hwloc=external \
          --with-libevent=external
        return
      fi
      if [[ "${mode}" == "external" ]]; then
        die "WITH_PMIX=external but pmix.h was not found (install libpmix-dev, or use WITH_PMIX=internal)"
      fi
      log "External PMIx headers not found; falling back to bundled PMIx"
      printf '%s\n' \
        --with-pmix=internal \
        --with-prrte=internal \
        --with-hwloc=internal \
        --with-libevent=internal
      return
      ;;
    /*)
      [[ -f "${mode}/include/pmix.h" ]] \
        || die "WITH_PMIX=${mode} but ${mode}/include/pmix.h is missing"
      log "Using external PMIx at ${mode}"
      printf '%s\n' \
        "--with-pmix=${mode}" \
        --with-hwloc=external \
        --with-libevent=external
      return
      ;;
    *)
      die "WITH_PMIX must be internal|external|auto|/path/to/pmix (got: ${mode})"
      ;;
  esac
}

download_and_unpack() {
  need_cmd wget
  need_cmd tar
  mkdir -p "${BUILD_ROOT}"
  cd "${BUILD_ROOT}"
  if [[ ! -f "${TARBALL}" ]]; then
    log "Downloading ${DOWNLOAD_URL}"
    wget -q --show-progress -O "${TARBALL}" "${DOWNLOAD_URL}" \
      || die "download failed; set OPENMPI_VERSION to a published release"
  else
    log "Using existing ${BUILD_ROOT}/${TARBALL}"
  fi
  rm -rf "${SRC_DIR}"
  log "Unpacking ${TARBALL}"
  tar xf "${TARBALL}"
  [[ -d "${SRC_DIR}" ]] || die "expected source dir missing: ${SRC_DIR}"
}

configure_build() {
  need_cmd make
  local -a support_flags=()
  mapfile -t support_flags < <(resolve_support_flags)
  log "Support library flags: ${support_flags[*]}"

  cd "${SRC_DIR}"
  log "Configuring Open MPI ${OPENMPI_VERSION} -> ${PREFIX}"
  # Clear stale cache if re-running in the same tree.
  rm -f config.cache
  ./configure \
    --prefix="${PREFIX}" \
    --enable-mpirun-prefix-by-default \
    --enable-mpi-fortran=yes \
    --enable-mpi-cxx=no \
    "${support_flags[@]}"
}

build_and_install() {
  cd "${SRC_DIR}"
  log "Building with -j${JOBS}"
  make -j"${JOBS}"
  log "Installing into ${PREFIX}"
  run_as_root mkdir -p "${PREFIX}"
  run_as_root make install
}

verify_install() {
  local mpicc="${PREFIX}/bin/mpicc"
  local mpirun="${PREFIX}/bin/mpirun"
  [[ -x "${mpicc}" ]] || die "mpicc not found at ${mpicc}"
  [[ -x "${mpirun}" ]] || die "mpirun not found at ${mpirun}"
  log "Installed Open MPI:"
  "${mpicc}" --showme:version || true
  "${mpirun}" --version || true
  if [[ -x "${PREFIX}/bin/ompi_info" ]]; then
    log "PMIx-related ompi_info lines:"
    "${PREFIX}/bin/ompi_info" --parsable 2>/dev/null | grep -i pmix | head -40 || true
  fi
}

cleanup() {
  if [[ "${KEEP_BUILD:-0}" == "1" ]]; then
    log "KEEP_BUILD=1; leaving ${BUILD_ROOT}"
    return 0
  fi
  log "Cleaning ${BUILD_ROOT}"
  rm -rf "${BUILD_ROOT}"
}

main() {
  log "Open MPI ${OPENMPI_VERSION} -> prefix=${PREFIX}, WITH_PMIX=${WITH_PMIX}"
  install_build_deps
  download_and_unpack
  configure_build
  build_and_install
  verify_install
  cleanup
  cat <<EOF

Open MPI installed under ${PREFIX}

Add to your environment (and to job scripts if needed):
  export PATH=${PREFIX}/bin:\$PATH
  export LD_LIBRARY_PATH=${PREFIX}/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}

Sky Port mounts host /opt into job containers, so ${PREFIX} is visible as /opt/openmpi.
EOF
}

main "$@"
