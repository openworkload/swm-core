# Build the example MPI hello binary into the user's home directory.
#
#   make -C c_src/examples/mpi
#   # installs $(HOME)/mpi_hello
#
# Requires host gcc and Open MPI under /opt/openmpi (see scripts/install-openmpi.sh).

OPENMPI_PREFIX ?= /opt/openmpi
MPICC          ?= $(OPENMPI_PREFIX)/bin/mpicc
INSTALL_DIR    ?= $(HOME)
TARGET         := $(INSTALL_DIR)/mpi_hello

.PHONY: all check clean

all: check $(TARGET)

check:
	@test -d "$(OPENMPI_PREFIX)" || \
	  { echo "ERROR: Open MPI not found at $(OPENMPI_PREFIX) (run scripts/install-openmpi.sh)" >&2; exit 1; }
	@test -x "$(MPICC)" || \
	  { echo "ERROR: mpicc not found at $(MPICC)" >&2; exit 1; }
	@command -v gcc >/dev/null 2>&1 || \
	  { echo "ERROR: gcc not found in PATH (needed by mpicc)" >&2; exit 1; }
	@echo "Dependencies OK: gcc=$$(command -v gcc), mpicc=$(MPICC)"

$(TARGET): mpi_hello.c
	@mkdir -p "$(INSTALL_DIR)"
	$(MPICC) -o "$@" "$<"
	@echo "Installed $@"

clean:
	rm -f "$(TARGET)"
	rm -rf "$(INSTALL_DIR)/mpi_hello.libs"
