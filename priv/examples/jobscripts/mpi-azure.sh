#!/bin/bash
set -euo pipefail

#SWM name Multi-node MPI example
#SWM nodes 3
#SWM relocatable
#SWM comment OpenMPI hello via swm-task --pmix (one rank per node)
#SWM flavor Standard_D4s_v3
#SWM cloud-image ubuntu-hpc/2404
#SWM container-image ubuntu:24.04

export PATH="/opt/openmpi/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/openmpi/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cat >mpi_hello.c <<'EOF'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank = 0, size = 0, name_len = 0;
    char name[MPI_MAX_PROCESSOR_NAME];
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(name, &name_len);
    printf("Hello from MPI rank %d/%d on %s\n", rank, size, name);
    fflush(stdout);
    MPI_Finalize();
    return 0;
}
EOF

mpicc -o mpi_hello mpi_hello.c

# One rank per allocated node; PMIx server is owned by SWM (swm-pmix).
swm-task --pmix ./mpi_hello
