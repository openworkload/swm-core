#!/bin/bash
set -euo pipefail

#SWM name Hello MPI Local
#SWM nodes 3
#SWM comment Local OpenMPI hello
#SWM account localhost
#SWM flavor localhost

echo "Hello from multi-node MPI job ${SWM_JOB_ID} (${SWM_JOB_NAME})"
echo "Nodes (${SWM_JOB_NODES_NUMBER}): ${SWM_JOB_NODES}"
echo "Launcher hostname: $(hostname)"
date

# The script expects openmpi (binaries + libs) is in /opt/openmpi on the host.
# Host /opt is bind-mounted into the job container.
export PATH="/opt/openmpi/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/openmpi/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

if ! command -v mpicc >/dev/null 2>&1; then
    echo "mpicc not found: install OpenMPI under /opt/openmpi on the compute host" >&2
    exit 1
fi

cat >mpi_hello.c <<'EOF'
#include <mpi.h>
#include <stdio.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);

    int rank = 0;
    int size = 0;
    int name_len = 0;
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

swm-task --pmix ./mpi_hello

echo "Multi-node MPI job completed"
