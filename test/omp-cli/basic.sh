#!/bin/bash
set -e

# Import test lib
source dev-container-features-test-lib

mkdir -p /root/.omp/agent
cat > /root/.omp/agent/models.json <<'EOF'
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [
        { "id": "llama3.1:8b" }
      ]
    }
  }
}
EOF

cat > /root/.omp/agent/settings.json <<'EOF'
{
  "enabledModels": ["ollama/*"],
  "theme": "dark"
}
EOF

# Tests
check "omp cli installed" command -v omp
check "omp wrapper is not a symlink" test ! -L /usr/local/bin/omp
check "omp init script installed" test -x /usr/local/lib/omp-cli/init-agent-config.sh
check "omp login shell exports isolated agent dir" bash -lc 'test "$PI_CODING_AGENT_DIR" = "/root/.omp-devcontainer/agent"'
check "omp login shell exports ollama host" bash -lc 'test "$OLLAMA_HOST" = "host.docker.internal:11434"'
check "omp version" omp --version
check "omp container agent dir seeded" test -f /root/.omp-devcontainer/agent/.seeded-from-host
check "omp source config unchanged" grep -q 'http://localhost:11434/v1' /root/.omp/agent/models.json
check "omp container config rewritten" grep -q 'http://host.docker.internal:11434/v1' /root/.omp-devcontainer/agent/models.json
check "omp container settings cleared enabledModels" sh -lc '! grep -q '"'"'enabledModels'"'"' /root/.omp-devcontainer/agent/settings.json'

reportResults