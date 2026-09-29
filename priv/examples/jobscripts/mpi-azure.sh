#!/bin/bash
set -euo pipefail

# Build the binary on the submit host first:
#   make -C c_src/examples/mpi
# Then submit; ~/mpi_hello is uploaded via input-files before the job starts.
#SWM name Multi-node MPI example
#SWM nodes 2
#SWM relocatable
#SWM comment OpenMPI hello via swm-task --pmix (one rank per node)
#SWM flavor Standard_D2_v4
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image swmregistry.azurecr.io/openworkload/ubuntu:24.04
#SWM storage swmblobcontainer
#SWM input-files ~/mpi_hello

MPI_HELLO="./mpi_hello"

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

export PATH="${OPENMPI_PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# HPC-X Open MPI is built with prefix /build-result/...; without these,
# MPI_Init fails looking for share/openmpi under that non-existent path.
export OPAL_PREFIX="${OPENMPI_PREFIX}"
export OMPI_PREFIX="${OPENMPI_PREFIX}"

# HPC-X component libs (ucx, hcoll, ompi, ...): covers libucp, libevent_*, etc.
if [[ -n "${HPCX_ROOT}" ]]; then
    for libdir in "${HPCX_ROOT}"/*/lib; do
        if [[ -d "${libdir}" ]]; then
            export LD_LIBRARY_PATH="${libdir}:${LD_LIBRARY_PATH}"
        fi
    done
fi

# Fallback: locate libevent_core if Open MPI was built against a separate tree.
if ! compgen -G "${OPENMPI_PREFIX}/lib/libevent_core*.so*" >/dev/null; then
    for d in /opt/hpcx-*/ompi/lib /opt/hpcx-*/openmpi/lib /opt/openmpi-*/lib /opt/openmpi/lib; do
        if [[ -d "${d}" ]] && compgen -G "${d}/libevent_core*.so*" >/dev/null; then
            export LD_LIBRARY_PATH="${d}:${LD_LIBRARY_PATH}"
            break
        fi
    done
fi

if [[ ! -x "${MPI_HELLO}" ]]; then
    echo "mpi_hello not found at ${MPI_HELLO} (expected upload via #SWM input-files)" >&2
    exit 1
fi

echo "Using Open MPI at ${OPENMPI_PREFIX}${HPCX_ROOT:+ (HPC-X ${HPCX_ROOT})}"

# Pass prefixes/libs into each rank (shell exports do not reach swm-task children).
swm-task --pmix env \
    "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}" \
    "PATH=${PATH}" \
    "OPAL_PREFIX=${OPAL_PREFIX}" \
    "OMPI_PREFIX=${OMPI_PREFIX}" \
    "${MPI_HELLO}"
