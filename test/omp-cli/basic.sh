#!/bin/bash
set -e

# Import test lib
source dev-container-features-test-lib

FEATURE_AGENT_DIR=/home/vscode/.omp-devcontainer/agent
FEATURE_PERSISTENCE_ROOT=/home/vscode/.omp-devcontainer
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

SOURCE_AGENT_DIR="$TEST_ROOT/source-agent"
CONTAINER_AGENT_DIR="$TEST_ROOT/container-agent"
WRAPPER_AGENT_DIR="$TEST_ROOT/wrapper-agent"
EMPTY_SOURCE_DIR="$TEST_ROOT/empty-source"

mkdir -p "$SOURCE_AGENT_DIR" "$EMPTY_SOURCE_DIR"
cat > "$SOURCE_AGENT_DIR/models.json" <<'EOF'
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

cat > "$SOURCE_AGENT_DIR/settings.json" <<'EOF'
{
  "enabledModels": ["ollama/*"],
  "theme": "dark"
}
EOF

# Tests
check "omp cli installed" command -v omp
check "omp wrapper is not a symlink" test ! -L /usr/local/bin/omp
check "omp init script installed" test -x /usr/local/lib/omp-cli/init-agent-config.sh
check "omp feature env points to persisted agent dir" test "$PI_CODING_AGENT_DIR" = "$FEATURE_AGENT_DIR"
check "omp feature persistence root is mounted" sh -lc 'test -d "$1" && mountpoint -q "$1"' sh "$FEATURE_PERSISTENCE_ROOT"
check "omp login shell exports ollama host" env OMP_SOURCE_AGENT_DIR="$EMPTY_SOURCE_DIR" PI_CODING_AGENT_DIR="$WRAPPER_AGENT_DIR" bash -lc 'test "$OLLAMA_HOST" = "host.docker.internal:11434"'
check "omp version" env OMP_SOURCE_AGENT_DIR="$EMPTY_SOURCE_DIR" PI_CODING_AGENT_DIR="$WRAPPER_AGENT_DIR" omp --version
check "omp init script seeds isolated agent dir" env OMP_SOURCE_AGENT_DIR="$SOURCE_AGENT_DIR" PI_CODING_AGENT_DIR="$CONTAINER_AGENT_DIR" /usr/local/lib/omp-cli/init-agent-config.sh
check "omp container agent dir seeded" test -f "$CONTAINER_AGENT_DIR/.seeded-from-host"
check "omp source config unchanged" grep -q 'http://localhost:11434/v1' "$SOURCE_AGENT_DIR/models.json"
check "omp container config rewritten" grep -q 'http://host.docker.internal:11434/v1' "$CONTAINER_AGENT_DIR/models.json"
check "omp container settings cleared enabledModels" sh -lc '! grep -q '"'"'enabledModels'"'"' "$1"' sh "$CONTAINER_AGENT_DIR/settings.json"

reportResults