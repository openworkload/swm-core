#!/bin/bash
set -euo pipefail

# Multi-node NCCL all-reduce over InfiniBand on Azure ND-series (GPU + IB).
# Requires Sky Port IB container support (CDI/devices, IPC_LOCK, memlock) and
# host /opt bind with HPC-X / nccl-tests / Microsoft topo files (ubuntu-hpc image).
#
#SWM name Azure NCCL IB test
#SWM nodes 2
#SWM gpus 4
#SWM relocatable
#SWM comment NCCL all_reduce_perf via swm-task --pmix (1 rank/node, -g 8)
#SWM flavor Standard_ND40rs_v2
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image nvcr.io/nvidia/pytorch:24.10-py3
#SWM storage swmblobcontainer
#SWM account azure

echo "NCCL IB job on $(hostname) id=${SWM_JOB_ID:-?} nodes=${SWM_JOB_NODES_NUMBER:-?}"

# Discover HPC-X / Open MPI under host /opt (bind-mounted into the container).
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
    for d in /opt/openmpi-* /opt/openmpi; do
        if [[ -d "${d}" && -x "${d}/bin/mpirun" ]]; then
            OPENMPI_PREFIX="${d}"
            break
        fi
    done
fi
if [[ -z "${OPENMPI_PREFIX}" ]]; then
    echo "Open MPI / HPC-X not found under /opt" >&2
    exit 1
fi

export PATH="${OPENMPI_PREFIX}/bin:${PATH}"
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

echo "Using Open MPI at ${OPENMPI_PREFIX}${HPCX_ROOT:+ (HPC-X ${HPCX_ROOT})}"

# Prefer prebuilt nccl-tests on the Azure HPC image; otherwise build with MPI.
NCCL_TEST=""
if [[ -x /opt/nccl-tests/build/all_reduce_perf ]]; then
    NCCL_TEST=/opt/nccl-tests/build/all_reduce_perf
elif [[ -x ./nccl-tests/build/all_reduce_perf ]]; then
    NCCL_TEST=./nccl-tests/build/all_reduce_perf
else
    echo "Building nccl-tests with MPI=1..."
    git clone --depth 1 https://github.com/NVIDIA/nccl-tests.git
    make -C nccl-tests -j"$(nproc)" MPI=1 \
        MPI_HOME="${OPENMPI_PREFIX}" \
        CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
    NCCL_TEST=./nccl-tests/build/all_reduce_perf
fi

TOPO=""
for f in /opt/microsoft/ndv4-topo.xml /opt/microsoft/ndv5-topo.xml /opt/microsoft/*-topo.xml; do
    if [[ -f "${f}" ]]; then
        TOPO="${f}"
        break
    fi
done

export CUDA_DEVICE_ORDER=PCI_BUS_ID
export NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-eth0}"
export NCCL_IB_DISABLE=0
if [[ -n "${TOPO}" ]]; then
    export NCCL_TOPO_FILE="${TOPO}"
    echo "NCCL_TOPO_FILE=${NCCL_TOPO_FILE}"
fi

# One PMIx rank per allocated node; all GPUs on the node via -g 8.
TASK_ENV=(
    env
    "PATH=${PATH}"
    "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
    "OPAL_PREFIX=${OPAL_PREFIX}"
    "OMPI_PREFIX=${OMPI_PREFIX}"
    "CUDA_DEVICE_ORDER=${CUDA_DEVICE_ORDER}"
    "NCCL_DEBUG=${NCCL_DEBUG}"
    "NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}"
    "NCCL_IB_DISABLE=${NCCL_IB_DISABLE}"
)
if [[ -n "${NCCL_TOPO_FILE:-}" ]]; then
    TASK_ENV+=("NCCL_TOPO_FILE=${NCCL_TOPO_FILE}")
fi
swm-task --pmix "${TASK_ENV[@]}" "${NCCL_TEST}" -b 8 -e 1G -f 2 -g 8
