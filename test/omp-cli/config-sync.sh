#!/usr/bin/env bash
set -euo pipefail

INIT_SCRIPT="${1:-/usr/local/lib/omp-cli/init-agent-config.sh}"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
SOURCE_AGENT_DIR="$TEST_ROOT/source-agent"
CONTAINER_AGENT_DIR="$TEST_ROOT/container-agent"
mkdir -p "$SOURCE_AGENT_DIR" "$CONTAINER_AGENT_DIR"

# Une configuration par défaut et un ancien marqueur ne doivent pas bloquer la copie.
printf 'theme: container-default\n' > "$CONTAINER_AGENT_DIR/config.yml"
touch "$CONTAINER_AGENT_DIR/.seeded-from-host"
cat > "$SOURCE_AGENT_DIR/config.yml" <<'EOF'
# Configuration hôte à conserver, filtre de modèles compris.
theme: host-dark
enabledModels:
  - ollama/*
modelRoles:
  default: ollama/example
providers:
  custom:
    baseUrl: http://127.0.0.1:9000/v1
EOF
cat > "$SOURCE_AGENT_DIR/models.yml" <<'EOF'
providers:
  ollama:
    baseUrl: http://localhost:11434/v1
  omlx:
    baseUrl: http://127.0.0.1:8000/v1
  ipv6:
    baseUrl: http://[::1]:8080/v1
  remote:
    baseUrl: https://models.example.com/v1
  alreadyRewritten:
    baseUrl: http://host.docker.internal:8000/v1
  flow: {baseUrl: http://localhost}
  lookalike:
    baseUrl: http://localhost.example.com/v1
EOF
cat > "$SOURCE_AGENT_DIR/models.json" <<'EOF'
{
  "providers": {
    "ollama": { "baseUrl": "http://localhost:11434/v1" },
    "other": { "baseUrl": "http://127.0.0.1:8000/v1" },
    "escaped": { "baseUrl": "http:\/\/localhost:8082\/v1" },
    "remote": { "baseUrl": "https://models.example.com/v1" }
  }
}
EOF
printf '{"enabledModels":["ollama/*"],"providers":{"custom":{"baseUrl":"http://localhost:9000/v1"}}}\n' > "$SOURCE_AGENT_DIR/settings.json"
printf '{"example":{"token":"synthetic-test-value"}}\n' > "$SOURCE_AGENT_DIR/auth.json"
printf 'EXAMPLE_VALUE=synthetic-test-value\n' > "$SOURCE_AGENT_DIR/.env"
chmod 600 "$SOURCE_AGENT_DIR/auth.json" "$SOURCE_AGENT_DIR/.env"
touch "$CONTAINER_AGENT_DIR/auth.json" "$CONTAINER_AGENT_DIR/.env"
chmod 644 "$CONTAINER_AGENT_DIR/auth.json" "$CONTAINER_AGENT_DIR/.env"

# La fusion des personnalisations doit garder les fichiers propres au conteneur.
for dir in agents skills hooks; do
    mkdir -p "$SOURCE_AGENT_DIR/$dir" "$CONTAINER_AGENT_DIR/$dir"
    printf 'host customization\n' > "$SOURCE_AGENT_DIR/$dir/shared.txt"
    printf 'old customization\n' > "$CONTAINER_AGENT_DIR/$dir/shared.txt"
    printf 'container customization\n' > "$CONTAINER_AGENT_DIR/$dir/container-only.txt"
done
for dir in sessions cache blobs terminal-sessions; do
    mkdir -p "$SOURCE_AGENT_DIR/$dir" "$CONTAINER_AGENT_DIR/$dir"
    printf 'host data\n' > "$SOURCE_AGENT_DIR/$dir/host-only.txt"
    printf 'container data\n' > "$CONTAINER_AGENT_DIR/$dir/container-only.txt"
done
for file in agent.db history.db other.db; do
    printf 'host database\n' > "$SOURCE_AGENT_DIR/$file"
    printf 'container database\n' > "$CONTAINER_AGENT_DIR/$file"
done
cp -R "$SOURCE_AGENT_DIR" "$TEST_ROOT/source-before"

sync_config() {
    env OMP_SOURCE_AGENT_DIR="$SOURCE_AGENT_DIR" PI_CODING_AGENT_DIR="$CONTAINER_AGENT_DIR" "$INIT_SCRIPT"
}

sync_config
bun - "$CONTAINER_AGENT_DIR" <<'EOF'
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
const read = name => readFileSync(join(process.argv[2], name), "utf8");
for (const name of ["auth.json", ".env"]) {
    assert.equal(statSync(join(process.argv[2], name)).mode & 0o777, 0o600, `${name} doit reprendre les permissions privées de la source`);
}
const config = Bun.YAML.parse(read("config.yml"));
assert.equal(config.theme, "host-dark", "la configuration hôte doit remplacer la configuration par défaut");
assert.equal(config.modelRoles.default, "ollama/example");
assert.deepEqual(config.enabledModels, ["ollama/*"]);
assert.equal(config.providers.custom.baseUrl, "http://host.docker.internal:9000/v1");
const models = Bun.YAML.parse(read("models.yml"));
for (const [provider, port] of [["ollama", 11434], ["omlx", 8000], ["ipv6", 8080], ["alreadyRewritten", 8000]]) {
    assert.equal(models.providers[provider].baseUrl, `http://host.docker.internal:${port}/v1`);
}
assert.equal(models.providers.remote.baseUrl, "https://models.example.com/v1");
assert.equal(models.providers.flow.baseUrl, "http://host.docker.internal");
assert.equal(models.providers.lookalike.baseUrl, "http://localhost.example.com/v1");
const legacyModels = JSON.parse(read("models.json"));
assert.equal(legacyModels.providers.ollama.baseUrl, "http://host.docker.internal:11434/v1");
assert.equal(legacyModels.providers.other.baseUrl, "http://host.docker.internal:8000/v1");
assert.equal(legacyModels.providers.escaped.baseUrl, "http://host.docker.internal:8082/v1");
assert.equal(legacyModels.providers.remote.baseUrl, "https://models.example.com/v1");
const settings = JSON.parse(read("settings.json"));
assert.deepEqual(settings.enabledModels, ["ollama/*"]);
assert.equal(settings.providers.custom.baseUrl, "http://host.docker.internal:9000/v1");
assert.ok(read("config.yml").startsWith("# Configuration hôte"), "les commentaires YAML doivent rester présents");
EOF
diff -r "$TEST_ROOT/source-before" "$SOURCE_AGENT_DIR"
cmp "$SOURCE_AGENT_DIR/auth.json" "$CONTAINER_AGENT_DIR/auth.json"
cmp "$SOURCE_AGENT_DIR/.env" "$CONTAINER_AGENT_DIR/.env"
for dir in agents skills hooks; do
    cmp "$SOURCE_AGENT_DIR/$dir/shared.txt" "$CONTAINER_AGENT_DIR/$dir/shared.txt"
    test "$(cat "$CONTAINER_AGENT_DIR/$dir/container-only.txt")" = 'container customization'
done
for dir in sessions cache blobs terminal-sessions; do
    test "$(cat "$CONTAINER_AGENT_DIR/$dir/container-only.txt")" = 'container data'
    test ! -e "$CONTAINER_AGENT_DIR/$dir/host-only.txt"
done
for file in agent.db history.db other.db; do
    test "$(cat "$CONTAINER_AGENT_DIR/$file")" = 'container database'
done

# La modification suivante de l'hôte doit être reprise, sans refaire un seed.
printf 'theme: host-updated\n' > "$SOURCE_AGENT_DIR/config.yml"
printf 'container edit\n' > "$CONTAINER_AGENT_DIR/models.yml"
cat > "$SOURCE_AGENT_DIR/settings.json" <<'EOF'
{
  // Un fichier JSON hérité peut contenir des commentaires et des virgules finales.
  "enabledModels": ["ollama/*"],
  "baseUrl": "http://localhost:9000/v1",
}
EOF
sync_config
test "$(cat "$CONTAINER_AGENT_DIR/config.yml")" = 'theme: host-updated'
bun -e 'import assert from "node:assert/strict"; assert.equal(Bun.YAML.parse(await Bun.file(process.argv[1]).text()).providers.omlx.baseUrl, "http://host.docker.internal:8000/v1")' "$CONTAINER_AGENT_DIR/models.yml"
bun -e 'import assert from "node:assert/strict"; const text = await Bun.file(process.argv[1]).text(); assert.ok(text.includes("// Un fichier JSON hérité")); assert.ok(text.includes("http://host.docker.internal:9000/v1")); assert.ok(text.endsWith(",\n}\n"))' "$CONTAINER_AGENT_DIR/settings.json"

# Une source absente laisse la configuration existante utilisable.
env OMP_SOURCE_AGENT_DIR="$TEST_ROOT/absent" PI_CODING_AGENT_DIR="$CONTAINER_AGENT_DIR" "$INIT_SCRIPT"
test "$(cat "$CONTAINER_AGENT_DIR/config.yml")" = 'theme: host-updated'

echo 'OK : configuration synchronisée, URLs réécrites, source et données du conteneur préservées.'
