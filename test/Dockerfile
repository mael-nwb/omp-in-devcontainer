FROM mcr.microsoft.com/devcontainers/base:ubuntu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git bash \
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
RUN mkdir -p /root/.omp/agent \
    && cat > /root/.omp/agent/models.json <<'EOF'
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "models": [
        { "id": "llama3.1:8b" }
      ]
    }
  }
}
EOF
RUN cat > /root/.omp/agent/settings.json <<'EOF'
{
  "enabledModels": ["ollama/*"],
  "theme": "dark"
}
EOF
RUN sh -lc "omp --version >/dev/null 2>&1"
RUN grep -q 'http://host.docker.internal:11434/v1' /root/.omp-devcontainer/agent/models.json
RUN sh -lc "! grep -q 'enabledModels' /root/.omp-devcontainer/agent/settings.json"

CMD ["bash"]
