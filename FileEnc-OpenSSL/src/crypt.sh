#!/usr/bin/env bash
# crypt.sh — encrypt/decrypt files using OpenSSL (AES-256-CBC + PBKDF2)
# shred plaintext from memory after successful encryption


set -Eeuo pipefail
IFS=$'\n\t'

CIPHER="aes-256-cbc"
PBKDF2_ITERATIONS=600000

usage() {
    cat <<EOF
Usage:
  crypt enc -i INPUT_FILE [-o OUTPUT_FILE]
  crypt dec -i INPUT_FILE [-o OUTPUT_FILE]

Modes:
  enc, encrypt    Encrypt input file
  dec, decrypt    Decrypt input file

Options:
  -i INPUT_FILE   Input file path (required)
  -o OUTPUT_FILE  Output file path (optional)

Defaults:
  - Encrypt output: INPUT_FILE.enc
  - Decrypt output: INPUT_FILE without trailing ".enc"
  - If decrypt input lacks ".enc", ".enc" is appended automatically

Crypto:
  - Cipher: ${CIPHER}
  - KDF: PBKDF2, iterations: ${PBKDF2_ITERATIONS}
  - Salt: enabled

Examples:
  crypt enc -i secrets.txt
  crypt dec -i secrets.txt.enc
  crypt enc -i file -o /tmp/file.enc
EOF
    exit 1
}

info()  { printf '[INFO] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

fatal() {
    error "$*"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fatal "Required command not found: $1"
}

require_cmd openssl

if command -v shred >/dev/null 2>&1; then
    SHRED_AVAILABLE=1
else
    SHRED_AVAILABLE=0
fi

restore_tty() {
    # if we changed terminal state, restore it. this is safe even if stdout isn't a tty.
    if [ -t 0 ]; then
        stty echo 2>/dev/null || true
    fi
}
trap restore_tty EXIT INT TERM

read_secret() {
    # reads a secret into a variable name (first arg).
    # works in interactive tty; supports piped input when non-tty.
    local __var="$1"
    local prompt="${2:-}"

    if [ -t 0 ]; then
        read -r -s -p "$prompt" "$__var"
        printf '\n'
    else
        read -r "$__var"
    fi
}

MODE="${1:-}"
shift || true

INPUT_FILE=""
OUTPUT_FILE=""

while getopts ":i:o:" opt; do
    case "$opt" in
        i) INPUT_FILE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        *) usage ;;
    esac
done

[ -n "$MODE" ] || usage
[ -n "$INPUT_FILE" ] || usage

case "$MODE" in
    enc|encrypt) MODE="enc" ;;
    dec|decrypt) MODE="dec" ;;
    *) fatal "Invalid mode: $MODE" ;;
esac

if [ "$MODE" = "dec" ] && [[ ! "$INPUT_FILE" =~ \.enc$ ]]; then
    INPUT_FILE="${INPUT_FILE}.enc"
fi

[ -f "$INPUT_FILE" ] || fatal "Input file does not exist: $INPUT_FILE"

if [ -z "$OUTPUT_FILE" ]; then
    if [ "$MODE" = "enc" ]; then
        OUTPUT_FILE="${INPUT_FILE}.enc"
    else
        OUTPUT_FILE="${INPUT_FILE%.enc}"
    fi
else
    if [ "$MODE" = "enc" ] && [[ ! "$OUTPUT_FILE" =~ \.enc$ ]]; then
        OUTPUT_FILE="${OUTPUT_FILE}.enc"
    fi
fi

[ "$INPUT_FILE" != "$OUTPUT_FILE" ] || fatal "Input and output must differ."

if [ -e "$OUTPUT_FILE" ]; then
    fatal "Output already exists: $OUTPUT_FILE (refusing to overwrite)"
fi

PASSWORD=""
PASSWORD_CONFIRM=""

read_secret PASSWORD "Enter password: "

if [ "$MODE" = "enc" ]; then
    read_secret PASSWORD_CONFIRM "Confirm password: "
    [ "$PASSWORD" = "$PASSWORD_CONFIRM" ] || fatal "Passwords do not match."
fi

if [ "$MODE" = "enc" ]; then
    info "Encrypting: $INPUT_FILE -> $OUTPUT_FILE"

    if ! openssl enc -"$CIPHER" -e -salt \
        -pbkdf2 -iter "$PBKDF2_ITERATIONS" \
        -in "$INPUT_FILE" \
        -out "$OUTPUT_FILE" \
        -pass "pass:$PASSWORD" 2> >(sed 's/^/[OPENSSL] /' >&2); then
        fatal "Encryption failed (see OpenSSL output above)."
    fi

    [ -s "$OUTPUT_FILE" ] || fatal "Encryption produced empty output: $OUTPUT_FILE"
    info "Encryption successful: $OUTPUT_FILE"

    if [ "$SHRED_AVAILABLE" -eq 1 ]; then
        if [ -t 0 ]; then
            read -r -p "Securely shred original file '$INPUT_FILE'? [y/N]: " CONFIRM
        else
            CONFIRM="n"
        fi
        case "${CONFIRM:-n}" in
            y|Y|yes|YES)
                info "Shredding original file..."
                shred --iterations=7 --random-source=/dev/urandom --remove --verbose "$INPUT_FILE"
                info "Original file removed."
                ;;
            *)
                info "Original file preserved."
                ;;
        esac
    else
        warn "shred not available. Original file preserved."
    fi

elif [ "$MODE" = "dec" ]; then
    info "Decrypting: $INPUT_FILE -> $OUTPUT_FILE"

    if ! openssl enc -d -"$CIPHER" \
        -pbkdf2 -iter "$PBKDF2_ITERATIONS" \
        -in "$INPUT_FILE" \
        -out "$OUTPUT_FILE" \
        -pass "pass:$PASSWORD" 2> >(sed 's/^/[OPENSSL] /' >&2); then
        fatal "Decryption failed (see OpenSSL output above)."
    fi

    [ -s "$OUTPUT_FILE" ] || fatal "Decryption produced empty output: $OUTPUT_FILE"
    info "Decryption successful: $OUTPUT_FILE"
fi

