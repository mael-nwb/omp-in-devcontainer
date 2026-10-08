ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/base:ubuntu
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git bash unzip \
    && rm -rf /var/lib/apt/lists/*

# Copie de la Feature locale et exécution de l'installateur.
COPY src/omp-cli /tmp/feature
RUN sh /tmp/feature/install.sh \
    && rm -rf /tmp/feature

# Vérifications rapides
RUN sh -lc "command -v omp >/dev/null 2>&1 || (echo 'omp introuvable' && exit 1)"
RUN sh -lc "test ! -L /usr/local/bin/omp"
RUN sh -lc "test -x /usr/local/lib/omp-cli/init-agent-config.sh"
RUN bash -lc 'test "$PI_CODING_AGENT_DIR" = "/root/.omp-devcontainer/agent"'
RUN bash -lc 'test "$OLLAMA_HOST" = "host.docker.internal:11434"'
# Même régression que le scénario Dev Container, sans dupliquer les fixtures.
COPY test/omp-cli/config-sync.sh /tmp/omp-config-sync-test.sh
RUN bash /tmp/omp-config-sync-test.sh

CMD ["bash"]
