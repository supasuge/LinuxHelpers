#!/usr/bin/env bash
#
# setup.sh — install encrypt.sh globally as `encrypt`
#

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="crypt"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC_PATH="${PROJECT_ROOT}/src/crypt.sh"

CANDIDATE_DIRS=(
    "$HOME/.local/bin"
    "/usr/local/bin"
)

info()    { echo "[INFO] $*"; }
success() { echo "[OK]   $*"; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

[ -f "$SRC_PATH" ] || error "Source script not found: $SRC_PATH"

if [ ! -x "$SRC_PATH" ]; then
    info "Making encrypt.sh executable"
    chmod +x "$SRC_PATH"
fi

INSTALL_DIR=""

for dir in "${CANDIDATE_DIRS[@]}"; do
    if echo "$PATH" | tr ':' '\n' | grep -qx "$dir"; then
        INSTALL_DIR="$dir"
        break
    fi
done

[ -n "$INSTALL_DIR" ] || error "No suitable directory found in PATH (checked: ${CANDIDATE_DIRS[*]})"

TARGET_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"

info "Selected install directory: $INSTALL_DIR"

# Ensure directory exists
if [ ! -d "$INSTALL_DIR" ]; then
    info "Creating $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" || error "Failed to create $INSTALL_DIR"
fi

if [ -e "$TARGET_PATH" ]; then
    if [ -L "$TARGET_PATH" ]; then
        info "Replacing existing symlink: $TARGET_PATH"
        rm "$TARGET_PATH"
    else
        error "$TARGET_PATH exists and is not a symlink. Refusing to overwrite."
    fi
fi

ln -s "$SRC_PATH" "$TARGET_PATH"

success "Installed crypt → $TARGET_PATH"

if command -v crypt >/dev/null 2>&1; then
    success "Command available: $(command -v encrypt)"
else
    error "Installation failed: encrypt not found in PATH"
fi

