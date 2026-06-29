#!/bin/sh
set -eu

OMP_INSTALLER_URL="https://omp.sh/install.sh"
BUN_INSTALLER_URL="https://bun.sh/install"
BUN_INSTALL_DIR="/usr/local/lib/omp-bun"
OMP_INSTALL_DIR="/usr/local/lib/omp-cli"
OMP_WRAPPER_DIR="/usr/local/lib/omp-cli"
OMP_REAL_BIN="$OMP_WRAPPER_DIR/omp-real"
OMP_REWRITE_SCRIPT="$OMP_WRAPPER_DIR/rewrite-models.mjs"
OMP_INIT_SCRIPT="$OMP_WRAPPER_DIR/init-agent-config.sh"
OMP_PROFILE_SCRIPT="/etc/profile.d/omp-devcontainer.sh"
readonly OMP_INSTALLER_URL BUN_INSTALLER_URL BUN_INSTALL_DIR OMP_INSTALL_DIR OMP_WRAPPER_DIR OMP_REAL_BIN OMP_REWRITE_SCRIPT OMP_INIT_SCRIPT OMP_PROFILE_SCRIPT

master() {
    echo "Activating feature 'omp-cli'"

    require_command curl
    require_command bash
    ensure_bun_runtime
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

ensure_bun_runtime() {
    if bun_runtime_is_supported; then
        expose_bun_command
        return 0
    fi

    install_standalone_bun
    export PATH="$BUN_INSTALL_DIR/bin:$PATH"
    expose_bun_command

    if bun_runtime_is_supported; then
        return 0
    fi

    echo "ERROR: Bun 1.3.14 or newer is required to install and run omp" >&2
    return 1
}

bun_runtime_is_supported() {
    if ! command -v bun >/dev/null 2>&1; then
        return 1
    fi

    bun -e 'const [major, minor, patch] = Bun.version.split(".").map(Number); process.exit(major > 1 || (major === 1 && (minor > 3 || (minor === 3 && patch >= 14))) ? 0 : 1)' >/dev/null 2>&1
}

install_standalone_bun() {
    mkdir -p "$BUN_INSTALL_DIR"
    curl -fsSL "$BUN_INSTALLER_URL" | BUN_INSTALL="$BUN_INSTALL_DIR" bash
}

expose_bun_command() {
    bun_path="$(command -v bun 2>/dev/null || true)"
    if [ -z "$bun_path" ] && [ -x "$BUN_INSTALL_DIR/bin/bun" ]; then
        bun_path="$BUN_INSTALL_DIR/bin/bun"
    fi

    if [ -z "$bun_path" ]; then
        echo "ERROR: Bun installation failed: bun command not found" >&2
        return 1
    fi

    ln -sfn "$bun_path" /usr/local/bin/bun
}

install_omp() {
    curl -fsSL "$OMP_INSTALLER_URL" | BUN_INSTALL="$BUN_INSTALL_DIR" PI_INSTALL_DIR="$OMP_INSTALL_DIR" PATH="$BUN_INSTALL_DIR/bin:$PATH" sh -s -- --source
}

expose_omp_command() {
    omp_path="$(command -v omp 2>/dev/null || true)"

    if [ -z "$omp_path" ] && [ -x "$BUN_INSTALL_DIR/bin/omp" ]; then
        omp_path="$BUN_INSTALL_DIR/bin/omp"
    fi

    if [ -z "$omp_path" ] && [ -x "$HOME/.bun/bin/omp" ]; then
        omp_path="$HOME/.bun/bin/omp"
    fi

    if [ -z "$omp_path" ] && [ -e "$OMP_INSTALL_DIR/omp" ]; then
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
#!/usr/bin/env bun
import { existsSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";

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

bun "\$OMP_REWRITE_SCRIPT" "\$OMP_CONTAINER_AGENT_DIR" \$clear_enabled_models_flag
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
