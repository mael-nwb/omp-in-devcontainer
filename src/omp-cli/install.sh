#!/bin/sh
set -eu

OMP_INSTALLER_URL="https://omp.sh/install.sh"
BUN_INSTALLER_URL="https://bun.sh/install"
BUN_INSTALL_DIR="/usr/local/lib/omp-bun"
MIN_BUN_VERSION="1.3.14"
OMP_INSTALL_DIR="/usr/local/lib/omp-cli"
OMP_WRAPPER_DIR="/usr/local/lib/omp-cli"
OMP_REAL_BIN="$OMP_WRAPPER_DIR/omp-real"
OMP_REWRITE_SCRIPT="$OMP_WRAPPER_DIR/rewrite-models.mjs"
OMP_INIT_SCRIPT="$OMP_WRAPPER_DIR/init-agent-config.sh"
OMP_PROFILE_SCRIPT="/etc/profile.d/omp-devcontainer.sh"
readonly OMP_INSTALLER_URL BUN_INSTALLER_URL BUN_INSTALL_DIR MIN_BUN_VERSION OMP_INSTALL_DIR OMP_WRAPPER_DIR OMP_REAL_BIN OMP_REWRITE_SCRIPT OMP_INIT_SCRIPT OMP_PROFILE_SCRIPT

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
        return 0
    fi

    install_standalone_bun
    export PATH="$BUN_INSTALL_DIR/bin:$PATH"
    expose_bun_command

    if bun_runtime_is_supported; then
        return 0
    fi

    echo "ERROR: Bun ${MIN_BUN_VERSION} or newer is required to install and run omp" >&2
    return 1
}

version_ge() {
    current="$1"
    minimum="$2"

    current_major="${current%%.*}"
    current_rest="${current#*.}"
    current_minor="${current_rest%%.*}"
    current_patch="${current_rest#*.}"
    current_patch="${current_patch%%-*}"

    minimum_major="${minimum%%.*}"
    minimum_rest="${minimum#*.}"
    minimum_minor="${minimum_rest%%.*}"
    minimum_patch="${minimum_rest#*.}"

    [ "$current_major" -ne "$minimum_major" ] && { [ "$current_major" -gt "$minimum_major" ]; return $?; }
    [ "$current_minor" -ne "$minimum_minor" ] && { [ "$current_minor" -gt "$minimum_minor" ]; return $?; }
    [ "$current_patch" -ge "$minimum_patch" ]
}

bun_runtime_is_supported() {
    if ! command -v bun >/dev/null 2>&1; then
        return 1
    fi

    version_raw="$(bun --version 2>/dev/null || true)"
    [ -n "$version_raw" ] || return 1
    version_ge "$version_raw" "$MIN_BUN_VERSION"
}

bun_platform_is_supported() {
    case "$(uname -s)" in
        Linux|Darwin) ;;
        *)
            echo "ERROR: Unsupported operating system for Bun: $(uname -s)" >&2
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64|arm64|aarch64) ;;
        *)
            echo "ERROR: Unsupported CPU architecture for Bun: $(uname -m)" >&2
            return 1
            ;;
    esac

    return 0
}

ensure_unzip_support() {
    if command -v unzip >/dev/null 2>&1; then
        return 0
    fi

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y --no-install-recommends unzip
        return 0
    fi

    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache unzip
        return 0
    fi

    echo "ERROR: unzip is required to install Bun" >&2
    return 1
}

install_standalone_bun() {
    bun_platform_is_supported
    ensure_unzip_support

    mkdir -p "$BUN_INSTALL_DIR"
    installer_tmp="$(mktemp -d "${TMPDIR:-/tmp}/omp-bun.XXXXXX")"
    # Download then execute (not `curl | bash`) so a fetch failure is caught
    # by `set -e` instead of being masked by the downstream shell exiting 0.
    curl -fsSL "$BUN_INSTALLER_URL" -o "$installer_tmp/install.sh"
    BUN_INSTALL="$BUN_INSTALL_DIR" bash "$installer_tmp/install.sh"
    rm -rf "$installer_tmp"
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

    if [ "$bun_path" = "/usr/local/bin/bun" ]; then
        return 0
    fi

    ln -sfn "$bun_path" /usr/local/bin/bun
}

install_omp() {
    installer_tmp="$(mktemp -d "${TMPDIR:-/tmp}/omp-install.XXXXXX")"
    # Download then execute (not `curl | sh`) so a fetch failure is caught by
    # `set -e` instead of being masked by the downstream shell exiting 0.
    curl -fsSL "$OMP_INSTALLER_URL" -o "$installer_tmp/install.sh"
    BUN_INSTALL="$BUN_INSTALL_DIR" PI_INSTALL_DIR="$OMP_INSTALL_DIR" PATH="$BUN_INSTALL_DIR/bin:$PATH" sh "$installer_tmp/install.sh" --source
    rm -rf "$installer_tmp"
}

expose_omp_command() {
    omp_path="$(command -v omp 2>/dev/null || true)"

    if [ -z "$omp_path" ] && [ -x "$BUN_INSTALL_DIR/bin/omp" ]; then
        omp_path="$BUN_INSTALL_DIR/bin/omp"
    fi

    if [ -z "$omp_path" ] && [ -x "$HOME/.bun/bin/omp" ]; then
        omp_path="$HOME/.bun/bin/omp"
    fi

    if [ -z "$omp_path" ] && [ -x "$OMP_INSTALL_DIR/omp" ]; then
        omp_path="$OMP_INSTALL_DIR/omp"
    fi

    if [ ! -e "$omp_path" ]; then
        echo "ERROR: omp CLI installation failed: omp command not found" >&2
        return 1
    fi
    # Preserve the target before replacing /usr/local/bin/omp with our wrapper.
    # Otherwise a symlink installed by omp would make the wrapper recursive.
    if [ "$omp_path" = "/usr/local/bin/omp" ] && [ -L "$omp_path" ]; then
        omp_path="$(readlink -f "$omp_path")"
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
import { existsSync, lstatSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from "fs";
import { join } from "path";

const agentDir = process.argv[2];
const sourceDir = process.argv[3];
if (!agentDir || !sourceDir) {
    throw new Error("Usage : rewrite-models.mjs <répertoire agent> <répertoire source>");
}

// Remplacement textuel : conserve les commentaires YAML/JSONC et le format de .env.
const localUrl = /(https?:\\?\/\\?\/(?:[^\s/"'@]+@)?)(?:localhost|127\.0\.0\.1|\[::1\])(?=[:/?#\s"',}\]]|$)/gi;
for (const filename of ["config.yml", "models.yml", "models.json", "settings.json", "auth.json", ".env"]) {
    const path = join(agentDir, filename);
    const sourcePath = join(sourceDir, filename);
    const hasSource = existsSync(sourcePath) && statSync(sourcePath).isFile();
    const inputPath = hasSource ? sourcePath : path;
    if (!existsSync(inputPath)) {
        continue;
    }
    if (existsSync(path) && lstatSync(path).isSymbolicLink()) {
        throw new Error(`Réécriture OMP refusée sur un lien symbolique : ${path}`);
    }
    const original = readFileSync(inputPath, "utf8");
    const rewritten = original.replace(localUrl, "$1host.docker.internal");
    if (hasSource || rewritten !== original) {
        // La copie garde les permissions, sans reprendre l'UID hôte ni suivre un lien destination.
        const temporaryPath = `${path}.tmp.${crypto.randomUUID()}`;
        try {
            writeFileSync(temporaryPath, rewritten, { mode: statSync(inputPath).mode & 0o777, flag: "wx" });
            renameSync(temporaryPath, path);
        } finally {
            if (existsSync(temporaryPath)) {
                unlinkSync(temporaryPath);
            }
        }
    }
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

export PI_CODING_AGENT_DIR="\$OMP_CONTAINER_AGENT_DIR"
mkdir -p "\$OMP_CONTAINER_AGENT_DIR"

if [ -d "\$OMP_SOURCE_AGENT_DIR" ]; then
    if [ "\$OMP_SOURCE_AGENT_DIR" -ef "\$OMP_CONTAINER_AGENT_DIR" ]; then
        echo "ERREUR : les répertoires OMP source et destination doivent être distincts." >&2
        exit 1
    fi

    # Seule la configuration est remplacée. Les sessions, bases et caches restent locaux.
    for dir in agents skills hooks; do
        if [ -d "\$OMP_SOURCE_AGENT_DIR/\$dir" ]; then
            if [ -L "\$OMP_CONTAINER_AGENT_DIR/\$dir" ]; then
                echo "ERREUR : synchronisation OMP refusée sur un lien symbolique : \$OMP_CONTAINER_AGENT_DIR/\$dir" >&2
                exit 1
            fi
            mkdir -p "\$OMP_CONTAINER_AGENT_DIR/\$dir"
            cp -R "\$OMP_SOURCE_AGENT_DIR/\$dir"/. "\$OMP_CONTAINER_AGENT_DIR/\$dir"/
        fi
    done
fi

bun "\$OMP_REWRITE_SCRIPT" "\$OMP_CONTAINER_AGENT_DIR" "\$OMP_SOURCE_AGENT_DIR"
EOF
    chmod +x "$OMP_INIT_SCRIPT"
}

install_omp_wrapper() {
    rm -f /usr/local/bin/omp
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
EOF
    chmod 644 "$OMP_PROFILE_SCRIPT"
}

master "$@"
