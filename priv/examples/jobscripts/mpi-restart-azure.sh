#!/bin/bash
set -euo pipefail

# Resume a previous MANA checkpoint from attached storage (new job; no auto-requeue).
# Point checkpoint-dir at the same path used by mpi-checkpoint-azure.sh.
# See HOWTO/CHECKPOINTS.md.
#SWM name MPI restart from MANA checkpoint
#SWM nodes 3
#SWM relocatable
#SWM comment mana_restart from /mnt/blob/ckpt
#SWM flavor Standard_D2_v4
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image swmregistry.azurecr.io/openworkload/ubuntu:24.04
#SWM storage swmblobcontainer
#SWM checkpoint dmtcp
#SWM checkpoint-dir /mnt/blob/ckpt

MANA_ROOT="${MANA_ROOT:-/opt/mana}"
CKPT_DIR="${SWM_CKPT_DIR:-/mnt/blob/ckpt}"

HPCX_ROOT=""
for d in /opt/hpcx-*; do
    if [[ -d "${d}" ]]; then
        HPCX_ROOT="${d}"
        break
    fi
done

OPENMPI_PREFIX=""
if [[ -n "${HPCX_ROOT}" ]]; then
    for d in "${HPCX_ROOT}/ompi" "${HPCX_ROOT}/openmpi" "${HPCX_ROOT}"/ompi-*; do
        if [[ -d "${d}" && -x "${d}/bin/mpirun" ]]; then
            OPENMPI_PREFIX="${d}"
            break
        fi
    done
fi
if [[ -z "${OPENMPI_PREFIX}" ]]; then
    for d in /opt/openmpi-*; do
        if [[ -d "${d}" && -x "${d}/bin/mpirun" ]]; then
            OPENMPI_PREFIX="${d}"
            break
        fi
    done
fi
if [[ -z "${OPENMPI_PREFIX}" && -d /opt/openmpi && -x /opt/openmpi/bin/mpirun ]]; then
    OPENMPI_PREFIX=/opt/openmpi
fi
if [[ -z "${OPENMPI_PREFIX}" ]]; then
    echo "Open MPI not found under /opt" >&2
    exit 1
fi

if [[ ! -x "${MANA_ROOT}/bin/mana_restart" ]]; then
    echo "MANA not found at ${MANA_ROOT}/bin" >&2
    exit 1
fi
if [[ ! -d "${CKPT_DIR}" ]]; then
    echo "Checkpoint directory missing: ${CKPT_DIR}" >&2
    exit 1
fi

export PATH="${MANA_ROOT}/bin:${OPENMPI_PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export OPAL_PREFIX="${OPENMPI_PREFIX}"
export OMPI_PREFIX="${OPENMPI_PREFIX}"

if [[ -n "${HPCX_ROOT}" ]]; then
    for libdir in "${HPCX_ROOT}"/*/lib; do
        if [[ -d "${libdir}" ]]; then
            export LD_LIBRARY_PATH="${libdir}:${LD_LIBRARY_PATH}"
        fi
    done
fi

echo "Restarting from ${CKPT_DIR} with MANA at ${MANA_ROOT}"

mana_coordinator --exit-on-finish &
COORD_PID=$!
sleep 2

cleanup() {
    if kill -0 "${COORD_PID}" 2>/dev/null; then
        kill "${COORD_PID}" 2>/dev/null || true
        wait "${COORD_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

swm-task --pmix env \
    "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}" \
    "PATH=${PATH}" \
    "OPAL_PREFIX=${OPAL_PREFIX}" \
    "OMPI_PREFIX=${OMPI_PREFIX}" \
    "DMTCP_CHECKPOINT_DIR=${CKPT_DIR}" \
    mana_restart --ckptdir "${CKPT_DIR}"
