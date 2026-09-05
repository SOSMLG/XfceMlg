#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  vscodiumDevSetup.sh — VSCodium C++/Python dev setup (optional)
#  Microsoft's cpptools is license-blocked from running on
#  VSCodium since April 2025, and Pylance is closed-source and
#  will never ship to Open VSX. Uses clangd+CodeLLDB and
#  basedpyright+Ruff instead — the combo the VSCodium community
#  actually settled on.
#  Privilege: sudo
# ══════════════════════════════════════════════════════════════
set -uo pipefail

R="\e[31m" G="\e[32m" Y="\e[33m" B="\e[34m" C="\e[36m" W="\e[1m" Z="\e[0m"
info()  { echo -e "${B}${W}[INFO]${Z} $*"; }
ok()    { echo -e "${G}${W}[ ✔ ]${Z} $*"; }
warn()  { echo -e "${Y}${W}[ ! ]${Z} $*"; }
err()   { echo -e "${R}${W}[ ✖ ]${Z} $*"; }
step()  { echo -e "\n${C}${W}══ $* ══${Z}"; }

[[ $EUID -eq 0 ]] && { err "Run this script as your normal user, not root."; exit 1; }

command -v sudo &>/dev/null || { err "sudo not found — this script needs it to install packages."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

ask() {
    local prompt="$1" default="${2:-Y}" reply hint="(Y/n)"
    [[ "$default" == "N" ]] && hint="(y/N)"
    read -rp "$(echo -e "${Y}${prompt} ${hint}: ${Z}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then ok "$label already installed."; return 0; fi
    info "$label: installing ${to_install[*]}"
    sudo apt-get install -y "${to_install[@]}" || warn "$label: some packages failed (continuing)."
}

install_ext() {
    local id="$1"
    info "Installing extension: $id"
    if codium --install-extension "$id" --force &>/dev/null; then
        ok "  $id"
    else
        warn "  Failed to install $id"
    fi
}

echo -e "\n${B}${W}══════ VSCodium C++/Python dev setup ══════${Z}"

if ! command -v codium &>/dev/null; then
    info "VSCodium not found, installing it first..."
    if [[ -f "$SCRIPT_DIR/installVscodium.sh" ]]; then
        bash "$SCRIPT_DIR/installVscodium.sh" || { err "VSCodium install failed, aborting."; exit 1; }
    else
        err "codium not installed and installVscodium.sh is missing."; exit 1
    fi
fi

sudo apt-get update -qq

step "1/4  C++ (clangd + CodeLLDB)"
if ask "Set up C++ (clangd + CodeLLDB — Microsoft's cpptools is blocked on VSCodium)?"; then
    install_pkgs "C++ toolchain" build-essential gdb clangd clang-format cmake
    install_ext "llvm-vs-code-extensions.vscode-clangd"
    install_ext "vadimcn.vscode-lldb"
    install_ext "twxs.cmake"
    install_ext "jeff-hykin.better-cpp-syntax"
fi

step "2/4  Python (basedpyright + Ruff)"
if ask "Set up Python (basedpyright + Ruff — Pylance can't ship to Open VSX)?"; then
    install_pkgs "Python toolchain" python3 python3-pip python3-venv
    install_ext "ms-python.python"
    install_ext "ms-python.debugpy"
    install_ext "detachhead.basedpyright"
    install_ext "charliermarsh.ruff"
fi

step "3/4  Settings"
if ask "Apply recommended settings (merged in — your existing settings are never overwritten)?"; then
    SETTINGS_DIR="$HOME/.config/VSCodium/User"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"
    mkdir -p "$SETTINGS_DIR"
    if [[ -f "$SETTINGS_FILE" ]]; then
        BACKUP="${SETTINGS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS_FILE" "$BACKUP"
        info "Existing settings.json backed up to $BACKUP"
    else
        echo "{}" > "$SETTINGS_FILE"
    fi

    python3 - "$SETTINGS_FILE" << 'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    content = f.read().strip()
data = json.loads(content) if content else {}
defaults = {
    "python.languageServer": "None",
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "editor.formatOnSave": True,
    "[python]": {"editor.defaultFormatter": "charliermarsh.ruff"},
    "[cpp]": {"editor.defaultFormatter": "llvm-vs-code-extensions.vscode-clangd"},
    "[c]": {"editor.defaultFormatter": "llvm-vs-code-extensions.vscode-clangd"},
    "clangd.arguments": ["--header-insertion=never"],
}
changed = False
for key, value in defaults.items():
    if key not in data:
        data[key] = value
        changed = True
    elif isinstance(value, dict) and isinstance(data.get(key), dict):
        for subkey, subvalue in value.items():
            if subkey not in data[key]:
                data[key][subkey] = subvalue
                changed = True
with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
print("changed" if changed else "unchanged")
PYEOF
    ok "settings.json updated at $SETTINGS_FILE"
fi

step "4/4  Starter project"
if ask "Create a starter project at ~/Projects/vscodium-starter?"; then
    PROJ_DIR="$HOME/Projects/vscodium-starter"
    if [[ -d "$PROJ_DIR" ]]; then
        warn "$PROJ_DIR already exists, leaving it untouched."
    else
        mkdir -p "$PROJ_DIR/.vscode"
        cat > "$PROJ_DIR/main.cpp" << 'EOF'
#include <iostream>

int main() {
    std::cout << "Hello from C++ — build with Ctrl+Shift+B, debug with F5\n";
    return 0;
}
EOF
        cat > "$PROJ_DIR/main.py" << 'EOF'
def main():
    print("Hello from Python — debug with F5")


if __name__ == "__main__":
    main()
EOF
        cat > "$PROJ_DIR/compile_flags.txt" << 'EOF'
-std=c++17
-Wall
-Wextra
-g
EOF
        cat > "$PROJ_DIR/.vscode/tasks.json" << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build main.cpp",
            "type": "shell",
            "command": "g++",
            "args": ["-std=c++17", "-Wall", "-Wextra", "-g", "main.cpp", "-o", "main"],
            "group": { "kind": "build", "isDefault": true },
            "problemMatcher": ["$gcc"]
        }
    ]
}
EOF
        cat > "$PROJ_DIR/.vscode/launch.json" << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "C++: build & debug main.cpp",
            "type": "lldb",
            "request": "launch",
            "program": "${workspaceFolder}/main",
            "args": [],
            "cwd": "${workspaceFolder}",
            "preLaunchTask": "build main.cpp"
        },
        {
            "name": "Python: debug main.py",
            "type": "debugpy",
            "request": "launch",
            "program": "${workspaceFolder}/main.py",
            "console": "integratedTerminal"
        }
    ]
}
EOF
        cat > "$PROJ_DIR/.vscode/settings.json" << 'EOF'
{
    "python.defaultInterpreterPath": "/usr/bin/python3"
}
EOF
        ok "Starter project created at $PROJ_DIR"
    fi
fi

ok "VSCodium C++/Python dev setup complete."
