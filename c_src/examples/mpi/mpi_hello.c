#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);

    int rank = 0;
    int size = 0;
    int name_len = 0;
    char name[MPI_MAX_PROCESSOR_NAME];

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(name, &name_len);

    const char *swm_rank = getenv("SWM_PMIX_RANK");
    if (swm_rank == NULL) {
        swm_rank = "?";
    }
    printf("Hello from MPI rank %d/%d (SWM rank %s) on %s\n", rank, size, swm_rank, name);
    fflush(stdout);

    MPI_Finalize();
    return 0;
}
