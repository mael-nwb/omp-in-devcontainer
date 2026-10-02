#!/bin/bash
set -e

# Bibliothèque de tests Dev Container
source dev-container-features-test-lib

FEATURE_AGENT_DIR=/home/vscode/.omp-devcontainer/agent
FEATURE_PERSISTENCE_ROOT=/home/vscode/.omp-devcontainer
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

WRAPPER_AGENT_DIR="$TEST_ROOT/wrapper-agent"
EMPTY_SOURCE_DIR="$TEST_ROOT/empty-source"
mkdir -p "$EMPTY_SOURCE_DIR"

# Vérifications
check "omp cli installed" command -v omp
check "omp wrapper is not a symlink" test ! -L /usr/local/bin/omp
check "omp init script installed" test -x /usr/local/lib/omp-cli/init-agent-config.sh
check "omp feature env points to persisted agent dir" test "$PI_CODING_AGENT_DIR" = "$FEATURE_AGENT_DIR"
check "omp feature persistence root is mounted" sh -lc 'test -d "$1" && mountpoint -q "$1"' sh "$FEATURE_PERSISTENCE_ROOT"
check "omp login shell exports ollama host" env OMP_SOURCE_AGENT_DIR="$EMPTY_SOURCE_DIR" PI_CODING_AGENT_DIR="$WRAPPER_AGENT_DIR" bash -lc 'test "$OLLAMA_HOST" = "host.docker.internal:11434"'
check "omp version" env OMP_SOURCE_AGENT_DIR="$EMPTY_SOURCE_DIR" PI_CODING_AGENT_DIR="$WRAPPER_AGENT_DIR" omp --version
check "omp host source is mounted" mountpoint -q /mnt/omp-host
check "omp host source is read-only" sh -c 'findmnt -n -o OPTIONS /mnt/omp-host | grep -Eq "(^|,)ro(,|$)"'
check "omp host configuration sync" bash "$(dirname "$0")/config-sync.sh"

reportResults
