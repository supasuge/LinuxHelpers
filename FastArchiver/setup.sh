#!/usr/bin/env bash
# setup.sh — install archiver globally as `archiver`
#  - Simplifies compression/decompression of fill directories

set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
SCRIPT_NAME="archiver"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC_PATH="${PROJECT_ROOT}/archiver"

CANDIDATE_DIRS=(
    "$HOME/.local/bin"
    "/usr/local/bin"
)

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
info()    { echo "[INFO] $*"; }
success() { echo "[OK]   $*"; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

# ------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------
[ -f "$SRC_PATH" ] || error "Source script not found: $SRC_PATH"

if [ ! -x "$SRC_PATH" ]; then
    info "Making archive_manager.sh executable"
    chmod +x "$SRC_PATH"
fi

# ------------------------------------------------------------
# Select install directory
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Install symlink
# ------------------------------------------------------------
if [ -e "$TARGET_PATH" ]; then
    if [ -L "$TARGET_PATH" ]; then
        info "Replacing existing symlink: $TARGET_PATH"
        rm "$TARGET_PATH"
    else
        error "$TARGET_PATH exists and is not a symlink. Refusing to overwrite."
    fi
fi

ln -s "$SRC_PATH" "$TARGET_PATH"

success "Installed ${SCRIPT_NAME} → $TARGET_PATH"

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------
if command -v "$SCRIPT_NAME" >/dev/null 2>&1; then
    success "Command available: $(command -v "$SCRIPT_NAME")"
else
    error "Installation failed: ${SCRIPT_NAME} not found in PATH"
fi

