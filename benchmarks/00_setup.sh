#!/bin/bash
# ============================================================
# Setup: Install dependencies and build benchmark tools
# Run this ONCE from the master node.
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

log "=== Cluster Benchmark Setup ==="

# --- 1. Create hostfiles ---
log "Creating hostfiles..."
cat > "${HOSTFILE_PCORES}" << 'EOF'
node1 slots=8
node2 slots=8
node3 slots=8
node4 slots=8
node5 slots=8
node6 slots=8
node7 slots=8
node8 slots=8
node9 slots=8
node10 slots=8
node11 slots=8
node12 slots=8
node13 slots=8
node14 slots=8
node15 slots=8
node16 slots=8
node17 slots=8
node18 slots=8
node19 slots=8
node20 slots=8
node21 slots=8
node22 slots=8
node23 slots=8
EOF

sed 's/slots=8/slots=12/' "${HOSTFILE_PCORES}" > "${HOSTFILE_ALLCORES}"
log "Hostfiles created at ${HOSTFILE_PCORES} and ${HOSTFILE_ALLCORES}"

# --- 2. Create shared benchmark directory ---
mkdir -p "${BENCH_DIR}" "${RESULTS_DIR}"

# --- 3. Install system packages on ALL nodes ---
log "Installing system packages on all nodes..."
PACKAGES="iperf3 fio hwloc libopenblas-dev libopenmpi-dev openmpi-bin gfortran build-essential cmake wget"
for node in "${COMPUTE_NODES[@]}" "${MASTER_HOST}"; do
    log "  Installing on ${node}..."
    ssh "${node}" "sudo apt-get update -qq && sudo apt-get install -y -qq ${PACKAGES}" &
done
wait
log "System packages installed on all nodes."

# --- 4. Build STREAM ---
log "Building STREAM..."
mkdir -p "${BENCH_DIR}/stream"
cd "${BENCH_DIR}/stream"
if [ ! -f stream.c ]; then
    wget -q https://www.cs.virginia.edu/stream/FTP/Code/stream.c
fi
# Compile with AVX2 + OpenMP, large array for 32GB systems
# Array size: 80M elements = ~1.8 GB (well above L3 cache of 25MB)
gcc -O3 -march=native -fopenmp -DSTREAM_ARRAY_SIZE=80000000 -DNTIMES=20 \
    stream.c -o stream_c
log "STREAM built at ${STREAM_BIN}"

# --- 5. Build OSU Micro-Benchmarks ---
log "Building OSU Micro-Benchmarks..."
cd "${BENCH_DIR}"
OSU_VERSION="7.3"
if [ ! -d "osu-micro-benchmarks-${OSU_VERSION}" ]; then
    wget -q "https://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-${OSU_VERSION}.tar.gz"
    tar xzf "osu-micro-benchmarks-${OSU_VERSION}.tar.gz"
fi
cd "osu-micro-benchmarks-${OSU_VERSION}"
if [ ! -f "${OSU_DIR}/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency" ]; then
    ./configure CC=mpicc CXX=mpicxx --prefix="${OSU_DIR}"
    make -j"$(nproc)"
    make install
fi
log "OSU Micro-Benchmarks built at ${OSU_DIR}"

# --- 6. Build HPL ---
log "Building HPL..."
cd "${BENCH_DIR}"
if [ ! -d "hpl-2.3" ]; then
    wget -q https://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz
    tar xzf hpl-2.3.tar.gz
fi
cd hpl-2.3

# Create a Make file for our cluster
cat > Make.cluster << 'HPLMAKE'
SHELL        = /bin/sh
CD           = cd
CP           = cp
LN_S         = ln -s
MKDIR        = mkdir
RM           = /bin/rm -f
TOUCH        = touch
ARCH         = cluster
TOPdir       = $(shell pwd)
INCdir       = $(TOPdir)/include
BINdir       = $(TOPdir)/bin/$(ARCH)
LIBdir       = $(TOPdir)/lib/$(ARCH)
HPLlib       = $(LIBdir)/libhpl.a
MPdir        = /usr/lib/x86_64-linux-gnu/openmpi
MPinc        = -I/usr/lib/x86_64-linux-gnu/openmpi/include
MPlib        = -lmpi
LAdir        = /usr/lib/x86_64-linux-gnu
LAinc        =
LAlib        = -lopenblas
F2CDEFS      = -DAdd_ -DF77_INTEGER=int -DStringSunStyle
HPL_INCLUDES = -I$(INCdir) -I$(INCdir)/$(ARCH) $(LAinc) $(MPinc)
HPL_LIBS     = $(HPLlib) $(LAlib) $(MPlib)
HPL_OPTS     = -DHPL_DETAILED_TIMING -DHPL_PROGRESS_REPORT
HPL_DEFS     = $(F2CDEFS) $(HPL_OPTS) $(HPL_INCLUDES)
CC           = mpicc
CCNOOPT      = $(HPL_DEFS)
CCFLAGS      = $(HPL_DEFS) -O3 -march=native -funroll-loops -ffast-math
LINKER       = mpicc
LINKFLAGS    = $(CCFLAGS)
ARCHIVER     = ar
ARFLAGS      = r
RANLIB       = echo
HPLMAKE

if [ ! -f "bin/cluster/xhpl" ]; then
    make arch=cluster -j"$(nproc)"
fi
log "HPL built at ${HPL_DIR}/bin/cluster/xhpl"

# --- 7. Build HPCG ---
log "Building HPCG..."
cd "${BENCH_DIR}"
if [ ! -d "hpcg-3.1" ]; then
    wget -q https://www.hpcg-benchmark.org/downloads/hpcg-3.1.tar.gz
    tar xzf hpcg-3.1.tar.gz
fi
cd hpcg-3.1
mkdir -p build
cd build
if [ ! -f xhpcg ]; then
    cmake .. -DCMAKE_CXX_COMPILER=mpicxx -DCMAKE_CXX_FLAGS="-O3 -march=native"
    make -j"$(nproc)"
fi
log "HPCG built at ${HPCG_DIR}/build/xhpcg"

# --- 8. Build IOR ---
log "Building IOR..."
cd "${BENCH_DIR}"
if [ ! -d "ior" ]; then
    git clone https://github.com/hpc/ior.git
fi
cd ior
if [ ! -f src/ior ]; then
    ./bootstrap
    ./configure --with-mpiio CC=mpicc
    make -j"$(nproc)"
fi
log "IOR built at ${BENCH_DIR}/ior/src/ior"

# --- 9. Distribute binaries via NFS ---
# Everything is already in /srv/cluster_shared, so all nodes can access it.
log ""
log "=== Setup Complete ==="
log "All tools built in ${BENCH_DIR} (NFS-shared)."
log "Hostfiles: ${HOSTFILE_PCORES}, ${HOSTFILE_ALLCORES}"
log ""
log "Run benchmarks in order:"
log "  1. ./01_stream.sh       (memory bandwidth)"
log "  2. ./02_network.sh      (iperf3)"
log "  3. ./03_osu_mpi.sh      (MPI latency/bandwidth/collectives)"
log "  4. ./04_hpl.sh          (LINPACK)"
log "  5. ./05_hpcg.sh         (conjugate gradient)"
log "  6. ./06_storage.sh      (fio + IOR)"
log "  7. ./07_collect.sh      (aggregate results)"
