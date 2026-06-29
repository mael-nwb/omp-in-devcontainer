#!/bin/bash
set -e

# Optional: Import test library
source dev-container-features-test-lib

# Feature-specific tests
check "node version" node --version
check "npm version" npm --version
check "omp cli installed" command -v omp
check "omp version" omp --version

# Report results
reportResults