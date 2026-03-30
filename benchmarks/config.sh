#!/bin/bash
# ============================================================
# Cluster Benchmark Configuration
# All scripts source this file for common settings.
# ============================================================

# --- Cluster topology ---
MASTER_HOST="master"
COMPUTE_NODES=(node{1..23})
NUM_COMPUTE=23

# --- Paths (NFS-shared) ---
SHARED_DIR="/srv/cluster_shared"
BENCH_DIR="${SHARED_DIR}/benchmarks"
RESULTS_DIR="${BENCH_DIR}/results"
HOSTFILE_PCORES="${SHARED_DIR}/hostfile_pcores"
HOSTFILE_ALLCORES="${SHARED_DIR}/hostfile_allcores"

# --- CPU pinning (i7-12700 Alder Lake) ---
# CPUs 0-15: P-cores (8 physical, 2 HT each) — max 4.8-4.9 GHz
# CPUs 16-19: E-cores (4 physical, no HT)  — max 3.6 GHz
PCORES_CPU_LIST="0-15"          # all P-core logical CPUs (with HT)
PCORES_PER_NODE=8               # physical P-cores
PCORES_THREADS_PER_NODE=16      # P-core logical CPUs (with HT)
ALLCORES_PER_NODE=12            # all physical cores
ECORES_CPU_LIST="16-19"         # E-core logical CPUs

# --- MPI settings ---
MPI_COMMON_ARGS="--hostfile ${HOSTFILE_PCORES} --bind-to core --map-by core --cpu-list ${PCORES_CPU_LIST}"
MPI_COMMON_ARGS_ALLCORES="--hostfile ${HOSTFILE_ALLCORES} --bind-to core --map-by core"

# --- Scaling node counts for multi-node benchmarks ---
SCALE_COUNTS=(1 2 4 8 16 23)

# --- Software paths (populated by setup.sh) ---
OSU_DIR="${BENCH_DIR}/osu-micro-benchmarks/install"
HPL_DIR="${BENCH_DIR}/hpl-2.3"
HPCG_DIR="${BENCH_DIR}/hpcg-3.1"
STREAM_BIN="${BENCH_DIR}/stream/stream_c"

# --- Benchmark repetitions ---
REPEAT=3  # number of times to repeat each benchmark for statistical confidence

# --- Helper functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

ensure_dirs() {
    mkdir -p "${RESULTS_DIR}"
}

# Generate a hostfile with only the first N nodes
make_hostfile_n() {
    local n=$1
    local slots=$2
    local outfile="${BENCH_DIR}/hostfile_n${n}_s${slots}"
    head -n "$n" "${HOSTFILE_PCORES}" | sed "s/slots=[0-9]*/slots=${slots}/" > "$outfile"
    echo "$outfile"
}
