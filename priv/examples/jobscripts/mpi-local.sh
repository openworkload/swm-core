#!/bin/bash
set -euo pipefail

# Build the binary on the host first:
#   make -C c_src/examples/mpi
#
# Local Sky Port has a single schedulable node (flavor=localhost). Requesting
# more than one node fails FCFS with "not enough nodes: N > 1". For multi-node
# MPI use mpi-azure.sh (cloud templates scale elastically).
#SWM name Hello MPI Local
#SWM nodes 1
#SWM comment Local OpenMPI hello (single-node)
#SWM account localhost
#SWM flavor localhost
#SWM container-image ubuntu:24.04

MPI_HELLO="${HOME}/mpi_hello"

echo "Hello from local MPI job ${SWM_JOB_ID} (${SWM_JOB_NAME})"
echo "Nodes (${SWM_JOB_NODES_NUMBER}): ${SWM_JOB_NODES}"
echo "Launcher hostname: $(hostname)"
date

# Prefer HPC-X Open MPI when present; else /opt/openmpi-* / /opt/openmpi.
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

export PATH="${OPENMPI_PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# HPC-X Open MPI may be built with a non-existent compile-time prefix.
export OPAL_PREFIX="${OPENMPI_PREFIX}"
export OMPI_PREFIX="${OPENMPI_PREFIX}"

if [[ -n "${HPCX_ROOT}" ]]; then
    for libdir in "${HPCX_ROOT}"/*/lib; do
        if [[ -d "${libdir}" ]]; then
            export LD_LIBRARY_PATH="${libdir}:${LD_LIBRARY_PATH}"
        fi
    done
fi

if ! compgen -G "${OPENMPI_PREFIX}/lib/libevent_core*.so*" >/dev/null; then
    for d in /opt/hpcx-*/ompi/lib /opt/hpcx-*/openmpi/lib /opt/openmpi-*/lib /opt/openmpi/lib; do
        if [[ -d "${d}" ]] && compgen -G "${d}/libevent_core*.so*" >/dev/null; then
            export LD_LIBRARY_PATH="${d}:${LD_LIBRARY_PATH}"
            break
        fi
    done
fi

if [[ ! -x "${MPI_HELLO}" ]]; then
    echo "mpi_hello not found at ${MPI_HELLO}; run: make -C c_src/examples/mpi" >&2
    exit 1
fi

echo "Using Open MPI at ${OPENMPI_PREFIX}${HPCX_ROOT:+ (HPC-X ${HPCX_ROOT})}"

swm-task --pmix env \
    "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}" \
    "PATH=${PATH}" \
    "OPAL_PREFIX=${OPAL_PREFIX}" \
    "OMPI_PREFIX=${OMPI_PREFIX}" \
    "${MPI_HELLO}"

echo "Local MPI job completed"
