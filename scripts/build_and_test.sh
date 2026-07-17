#!/usr/bin/env bash
set -euo pipefail

# Construire l'image de test basée sur Ubuntu sans Bun préinstallé.
docker build -t omp-feature-test -f test/Dockerfile .

# Vérifier le chemin où une version compatible de Bun est déjà dans le PATH.
docker build -t omp-feature-test-preinstalled-bun \
    --build-arg BASE_IMAGE=oven/bun:1.3.14-debian \
    -f test/Dockerfile .

# Exécuter quelques checks runtime de base
docker run --rm omp-feature-test sh -lc "omp --version >/dev/null && test ! -L /usr/local/bin/omp"
docker run --rm omp-feature-test bash -lc 'test "$PI_CODING_AGENT_DIR" = "/root/.omp-devcontainer/agent"'
docker run --rm omp-feature-test bash -lc 'test "$OLLAMA_HOST" = "host.docker.internal:11434"'
docker run --rm omp-feature-test-preinstalled-bun sh -lc "omp --version >/dev/null && test ! -L /usr/local/bin/omp"

echo "OK: omp est disponible et le mode .omp-devcontainer est actif dans l'image de test."