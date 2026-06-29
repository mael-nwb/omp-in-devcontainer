#!/bin/sh
set -eu

OMP_INSTALLER_URL="https://omp.sh/install.sh"
NODE_DIST_URL="https://nodejs.org/dist/latest-v22.x"
NODE_INSTALL_DIR="/usr/local/lib/omp-node"
OMP_INSTALL_DIR="/usr/local/lib/omp-cli"
OMP_WRAPPER_DIR="/usr/local/lib/omp-cli"
OMP_REAL_BIN="$OMP_WRAPPER_DIR/omp-real"
OMP_REWRITE_SCRIPT="$OMP_WRAPPER_DIR/rewrite-models.mjs"
OMP_INIT_SCRIPT="$OMP_WRAPPER_DIR/init-agent-config.sh"
OMP_PROFILE_SCRIPT="/etc/profile.d/omp-devcontainer.sh"
readonly OMP_INSTALLER_URL NODE_DIST_URL NODE_INSTALL_DIR OMP_INSTALL_DIR OMP_WRAPPER_DIR OMP_REAL_BIN OMP_REWRITE_SCRIPT OMP_INIT_SCRIPT OMP_PROFILE_SCRIPT

master() {
    echo "Activating feature 'omp-cli'"

    require_command curl
    require_command tar
    ensure_node_runtime
    install_omp
    expose_omp_command

    if command -v omp >/dev/null 2>&1; then
        omp --version || true
        return 0
    fi

    echo "ERROR: omp CLI installation failed: omp command not found" >&2
    return 1
}

require_command() {
    command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    echo "ERROR: Required command not found: $command_name" >&2
    return 1
}

ensure_node_runtime() {
    if node_runtime_is_supported; then
        return 0
    fi

    install_standalone_node
    export PATH="$NODE_INSTALL_DIR/current/bin:$PATH"

    if node_runtime_is_supported; then
        return 0
    fi

    echo "ERROR: Node.js 22.19.0 or newer with npm is required to run the omp config rewrite script" >&2
    return 1
}

node_runtime_is_supported() {
    if ! command -v node >/dev/null 2>&1; then
        return 1
    fi

    if ! command -v npm >/dev/null 2>&1; then
        return 1
    fi

    node -e 'const [major, minor, patch] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && (minor > 19 || (minor === 19 && patch >= 0))) ? 0 : 1)' >/dev/null 2>&1
}

install_standalone_node() {
    node_platform="$(detect_node_platform)"
    node_arch="$(detect_node_arch)"
    node_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/omp-node.XXXXXX")"
    checksum_file="$node_tmp_dir/SHASUMS256.txt"

    ensure_xz_support

    curl -fsSL "$NODE_DIST_URL/SHASUMS256.txt" -o "$checksum_file"
    node_file="$(find_node_archive "$checksum_file" "$node_platform" "$node_arch")"

    if [ -z "$node_file" ]; then
        echo "ERROR: No Node.js archive found for ${node_platform}-${node_arch}" >&2
        return 1
    fi

    mkdir -p "$NODE_INSTALL_DIR"
    curl -fsSL "$NODE_DIST_URL/$node_file" -o "$node_tmp_dir/$node_file"
    verify_node_archive "$node_tmp_dir" "$node_file"
    tar -xf "$node_tmp_dir/$node_file" -C "$NODE_INSTALL_DIR"
    ln -sfn "$NODE_INSTALL_DIR/${node_file%.tar.xz}" "$NODE_INSTALL_DIR/current"
    ln -sfn "$NODE_INSTALL_DIR/current/bin/node" /usr/local/bin/node
    ln -sfn "$NODE_INSTALL_DIR/current/bin/npm" /usr/local/bin/npm
    ln -sfn "$NODE_INSTALL_DIR/current/bin/npx" /usr/local/bin/npx
    rm -rf "$node_tmp_dir"
}

detect_node_platform() {
    case "$(uname -s)" in
        Linux) echo "linux" ;;
        Darwin) echo "darwin" ;;
        *)
            echo "ERROR: Unsupported operating system: $(uname -s)" >&2
            return 1
            ;;
    esac
}

detect_node_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x64" ;;
        arm64|aarch64) echo "arm64" ;;
        armv7l) echo "armv7l" ;;
        *)
            echo "ERROR: Unsupported CPU architecture: $(uname -m)" >&2
            return 1
            ;;
    esac
}

ensure_xz_support() {
    if command -v xz >/dev/null 2>&1; then
        return 0
    fi

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y --no-install-recommends xz-utils
        return 0
    fi

    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache xz
        return 0
    fi

    echo "ERROR: xz is required to extract the Node.js archive" >&2
    return 1
}

find_node_archive() {
    checksum_file="$1"
    node_platform="$2"
    node_arch="$3"

    awk -v suffix="-$node_platform-$node_arch.tar.xz" '
        index($2, "node-v") == 1 && substr($2, length($2) - length(suffix) + 1) == suffix { print $2; exit }
    ' "$checksum_file"
}

verify_node_archive() {
    node_tmp_dir="$1"
    node_file="$2"
    selected_checksum_file="$node_tmp_dir/SHASUMS256.selected"

    awk -v file="$node_file" '$2 == file { print }' "$node_tmp_dir/SHASUMS256.txt" > "$selected_checksum_file"

    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$node_tmp_dir" && sha256sum -c "$(basename "$selected_checksum_file")")
        return 0
    fi

    if command -v shasum >/dev/null 2>&1; then
        (cd "$node_tmp_dir" && shasum -a 256 -c "$(basename "$selected_checksum_file")")
        return 0
    fi

    echo "ERROR: No SHA-256 checksum tool found" >&2
    return 1
}

install_omp() {
    # omp ships a self-contained Rust binary; when bun is absent the installer
    # falls back to the prebuilt binary and drops it into PI_INSTALL_DIR.
    curl -fsSL "$OMP_INSTALLER_URL" | PI_INSTALL_DIR="$OMP_INSTALL_DIR" sh
}

expose_omp_command() {
    omp_path="$(command -v omp 2>/dev/null || true)"

    if [ -z "$omp_path" ]; then
        omp_path="$OMP_INSTALL_DIR/omp"
    fi

    if [ ! -e "$omp_path" ]; then
        echo "ERROR: omp CLI installation failed: omp command not found" >&2
        return 1
    fi

    mkdir -p "$OMP_WRAPPER_DIR"
    ln -sfn "$omp_path" "$OMP_REAL_BIN"
    install_models_rewrite_script
    install_agent_init_script
    install_omp_wrapper
    install_shell_profile
}

install_models_rewrite_script() {
    cat > "$OMP_REWRITE_SCRIPT" <<'EOF'
#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const agentDir = process.argv[2];
const clearEnabledModels = process.argv.includes("--clear-enabled-models");
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

if (!agentDir) {
    process.exit(1);
}

main();

function main() {
    const modelsPath = join(agentDir, "models.json");
    const settingsPath = join(agentDir, "settings.json");

    const models = readJsonFile(modelsPath);
    if (isRecord(models)) {
        const providers = models.providers;
        if (isRecord(providers)) {
            const ollama = providers.ollama;
            if (isRecord(ollama) && typeof ollama.baseUrl === "string") {
                try {
                    const url = new URL(ollama.baseUrl);
                    if (LOCAL_HOSTS.has(url.hostname)) {
                        url.hostname = "host.docker.internal";
                        ollama.baseUrl = url.toString();
                        writeJsonFile(modelsPath, models);
                    }
                } catch {
                    // Ignore invalid URLs and let omp surface the original config error.
                }
            }
        }
    }

    if (!clearEnabledModels) {
        return;
    }

    const settings = readJsonFile(settingsPath);
    if (!isRecord(settings) || !("enabledModels" in settings)) {
        return;
    }

    delete settings.enabledModels;
    writeJsonFile(settingsPath, settings);
}

function readJsonFile(path) {
    if (!existsSync(path)) {
        return undefined;
    }

    try {
        return JSON.parse(normalizeJsonLike(readFileSync(path, "utf8")));
    } catch {
        return undefined;
    }
}

function writeJsonFile(path, value) {
    writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeJsonLike(input) {
    return stripTrailingCommas(stripJsonComments(input));
}

function stripJsonComments(input) {
    let output = "";
    let inString = false;
    let isEscaped = false;
    let inLineComment = false;
    let inBlockComment = false;

    for (let index = 0; index < input.length; index += 1) {
        const current = input[index];
        const next = input[index + 1] ?? "";

        if (inLineComment) {
            if (current === "\n") {
                inLineComment = false;
                output += current;
            }
            continue;
        }

        if (inBlockComment) {
            if (current === "*" && next === "/") {
                inBlockComment = false;
                index += 1;
            }
            continue;
        }

        if (inString) {
            output += current;
            if (isEscaped) {
                isEscaped = false;
                continue;
            }
            if (current === "\\") {
                isEscaped = true;
                continue;
            }
            if (current === "\"") {
                inString = false;
            }
            continue;
        }

        if (current === "/" && next === "/") {
            inLineComment = true;
            index += 1;
            continue;
        }

        if (current === "/" && next === "*") {
            inBlockComment = true;
            index += 1;
            continue;
        }

        output += current;
        if (current === "\"") {
            inString = true;
        }
    }

    return output;
}

function stripTrailingCommas(input) {
    let output = "";
    let inString = false;
    let isEscaped = false;

    for (let index = 0; index < input.length; index += 1) {
        const current = input[index];

        if (inString) {
            output += current;
            if (isEscaped) {
                isEscaped = false;
                continue;
            }
            if (current === "\\") {
                isEscaped = true;
                continue;
            }
            if (current === "\"") {
                inString = false;
            }
            continue;
        }

        if (current === "\"") {
            inString = true;
            output += current;
            continue;
        }

        if (current === ",") {
            let cursor = index + 1;
            while (cursor < input.length && /\s/.test(input[cursor])) {
                cursor += 1;
            }
            if (input[cursor] === "]" || input[cursor] === "}") {
                continue;
            }
        }

        output += current;
    }

    return output;
}
EOF
    chmod +x "$OMP_REWRITE_SCRIPT"
}

install_agent_init_script() {
    cat > "$OMP_INIT_SCRIPT" <<EOF
#!/bin/sh
set -eu

OMP_REWRITE_SCRIPT="$OMP_REWRITE_SCRIPT"
OMP_SOURCE_AGENT_DIR="\${OMP_SOURCE_AGENT_DIR:-\$HOME/.omp/agent}"
OMP_CONTAINER_AGENT_DIR="\${PI_CODING_AGENT_DIR:-\$HOME/.omp-devcontainer/agent}"
OMP_SEEDED_MARKER="\$OMP_CONTAINER_AGENT_DIR/.seeded-from-host"

export PI_CODING_AGENT_DIR="\$OMP_CONTAINER_AGENT_DIR"
mkdir -p "\$OMP_CONTAINER_AGENT_DIR"

clear_enabled_models_flag=""
if [ -d "\$OMP_SOURCE_AGENT_DIR" ] && [ ! -e "\$OMP_SEEDED_MARKER" ]; then
    if [ -z "\$(ls -A "\$OMP_CONTAINER_AGENT_DIR" 2>/dev/null)" ]; then
        cp -R "\$OMP_SOURCE_AGENT_DIR"/. "\$OMP_CONTAINER_AGENT_DIR"/
        clear_enabled_models_flag="--clear-enabled-models"
    fi
    : > "\$OMP_SEEDED_MARKER"
fi

node "\$OMP_REWRITE_SCRIPT" "\$OMP_CONTAINER_AGENT_DIR" \$clear_enabled_models_flag
EOF
    chmod +x "$OMP_INIT_SCRIPT"
}

install_omp_wrapper() {
    cat > /usr/local/bin/omp <<EOF
#!/bin/sh
set -eu

OMP_REAL_BIN="$OMP_REAL_BIN"
OMP_INIT_SCRIPT="$OMP_INIT_SCRIPT"

if [ -x "\$OMP_INIT_SCRIPT" ]; then
    "\$OMP_INIT_SCRIPT"
fi

exec "\$OMP_REAL_BIN" "\$@"
EOF
    chmod +x /usr/local/bin/omp
}

install_shell_profile() {
    cat > "$OMP_PROFILE_SCRIPT" <<EOF
export PI_CODING_AGENT_DIR="\${PI_CODING_AGENT_DIR:-\$HOME/.omp-devcontainer/agent}"
export OLLAMA_HOST="\${OLLAMA_HOST:-host.docker.internal:11434}"
export OLLAMA_BASE_URL="\${OLLAMA_BASE_URL:-http://host.docker.internal:11434}"
if [ -x "$OMP_INIT_SCRIPT" ]; then
    "$OMP_INIT_SCRIPT" >/dev/null 2>&1 || true
fi
EOF
    chmod 644 "$OMP_PROFILE_SCRIPT"
}

master "$@"