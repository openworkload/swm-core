#!/bin/bash
set -euo pipefail

# Multi-node MPI with DMTCP/MANA checkpointing (cancel writes images under /mnt/blob).
# Build the binary on the submit host first:
#   make -C c_src/examples/mpi
# Then submit; ~/mpi_hello is uploaded via input-files before the job starts.
# See HOWTO/CHECKPOINTS.md.
#SWM name MPI checkpoint example (DMTCP/MANA)
#SWM nodes 3
#SWM relocatable
#SWM comment OpenMPI hello under MANA; cancel triggers final checkpoint
#SWM flavor Standard_D2_v4
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image swmregistry.azurecr.io/openworkload/ubuntu:24.04
#SWM storage swmblobcontainer
#SWM checkpoint dmtcp
#SWM checkpoint-dir /mnt/blob/ckpt
#SWM input-files ~/mpi_hello

MPI_HELLO="./mpi_hello"
MANA_ROOT="${MANA_ROOT:-/opt/mana}"
CKPT_DIR="${SWM_CKPT_DIR:-/mnt/blob/ckpt}"

# Azure HPC: prefer NVIDIA HPC-X tree (Open MPI + UCX + libevent, IB-ready).
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
    echo "Open MPI not found under /opt/hpcx-*/ompi, /opt/openmpi-*, or /opt/openmpi" >&2
    exit 1
fi

if [[ ! -x "${MANA_ROOT}/bin/mana_launch" ]]; then
    echo "MANA not found at ${MANA_ROOT}/bin (cloud-init installs it when #SWM checkpoint dmtcp is set)" >&2
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

if [[ ! -x "${MPI_HELLO}" ]]; then
    echo "mpi_hello not found at ${MPI_HELLO} (expected upload via #SWM input-files)" >&2
    exit 1
fi

mkdir -p "${CKPT_DIR}"
echo "Using Open MPI at ${OPENMPI_PREFIX}; MANA at ${MANA_ROOT}; ckpt dir ${CKPT_DIR}"

# Coordinator on main; ranks connect via MANA defaults / .mana.rc
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
    mana_launch "${MPI_HELLO}"
