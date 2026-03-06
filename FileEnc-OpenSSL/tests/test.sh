#!/usr/bin/env bash
#
# test.sh — Comprehensive test suite for encrypt.sh
# Provides verbose output to verify encryption/decryption workflow
#

set -Euo pipefail

# -----------------------------
# ANSI Color Codes
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# -----------------------------
# Test Configuration
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCRYPT_SCRIPT="${SCRIPT_DIR}/../src/encrypt.sh"
TEST_DIR="${SCRIPT_DIR}/test_workspace"
TEST_PASSWORD="TestP@ssw0rd!2024"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# -----------------------------
# Utility Functions
# -----------------------------
log_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

log_subheader() {
    echo -e "\n${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_verbose() {
    echo -e "${YELLOW}[VERBOSE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
}

log_failure() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Record test result
record_test() {
    local name="$1"
    local result="$2"  # 0 = pass, 1 = fail
    
    ((TESTS_TOTAL++))
    
    if [ "$result" -eq 0 ]; then
        ((TESTS_PASSED++))
        log_success "$name"
    else
        ((TESTS_FAILED++))
        log_failure "$name"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test workspace..."
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        log_verbose "Removed: $TEST_DIR"
    fi
}

# Setup test environment
setup() {
    log_header "TEST ENVIRONMENT SETUP"
    
    # Check if encrypt.sh exists
    if [ ! -f "$ENCRYPT_SCRIPT" ]; then
        log_failure "encrypt.sh not found at: $ENCRYPT_SCRIPT"
        exit 1
    fi
    log_verbose "Found encrypt.sh at: $ENCRYPT_SCRIPT"
    
    # Make executable
    chmod +x "$ENCRYPT_SCRIPT"
    log_verbose "Set executable permission on encrypt.sh"
    
    # Create test directory
    cleanup
    mkdir -p "$TEST_DIR"
    log_verbose "Created test workspace: $TEST_DIR"
    
    # Check OpenSSL version
    log_info "OpenSSL version:"
    openssl version
    echo ""
    
    # Check for shred availability
    if command -v shred >/dev/null 2>&1; then
        log_verbose "shred command: available"
    else
        log_warning "shred command: not available (shred tests will be skipped)"
    fi
}

# Helper to run encrypt.sh with password automation
run_encrypt() {
    local mode="$1"
    local input="$2"
    local output="${3:-}"
    local password="$4"
    local confirm_password="${5:-$password}"
    local extra_input="${6:-n}"  # For shred prompt, default 'n'
    
    local cmd_args=("$ENCRYPT_SCRIPT" "$mode" "-i" "$input")
    [ -n "$output" ] && cmd_args+=("-o" "$output")
    
    log_verbose "Running: ${cmd_args[*]}"
    
    if [ "$mode" = "enc" ] || [ "$mode" = "encrypt" ]; then
        # Encryption: password + confirm + shred prompt
        printf '%s\n%s\n%s\n' "$password" "$confirm_password" "$extra_input" | "${cmd_args[@]}" 2>&1
    else
        # Decryption: just password
        printf '%s\n' "$password" | "${cmd_args[@]}" 2>&1
    fi
}

# -----------------------------
# Test Cases
# -----------------------------

test_basic_encryption() {
    log_subheader "Test 1: Basic Encryption"
    
    local test_file="$TEST_DIR/test_basic.txt"
    local test_content="This is a basic test file for encryption."
    
    # Create test file
    echo "$test_content" > "$test_file"
    log_verbose "Created test file: $test_file"
    log_verbose "Content: $test_content"
    log_verbose "File size: $(wc -c < "$test_file") bytes"
    
    # Run encryption
    log_info "Encrypting file..."
    local output
    output=$(run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n")
    echo "$output"
    
    # Verify encrypted file exists
    if [ -f "${test_file}.enc" ]; then
        log_verbose "Encrypted file created: ${test_file}.enc"
        log_verbose "Encrypted file size: $(wc -c < "${test_file}.enc") bytes"
        
        # Show first 64 bytes in hex (should show "Salted__" magic bytes)
        log_verbose "Encrypted file header (hex):"
        if command -v xxd >/dev/null 2>&1; then
            xxd -l 64 "${test_file}.enc" || true
        elif command -v hexdump >/dev/null 2>&1; then
            hexdump -C -n 64 "${test_file}.enc" || true
        elif command -v od >/dev/null 2>&1; then
            od -A x -t x1z -v -N 64 "${test_file}.enc" || true
        else
            log_warning "No hex dump utility available (xxd, hexdump, or od)"
        fi
        
        record_test "Basic encryption creates .enc file" 0
    else
        record_test "Basic encryption creates .enc file" 1
    fi
}

test_basic_decryption() {
    log_subheader "Test 2: Basic Decryption"
    
    local encrypted_file="$TEST_DIR/test_basic.txt.enc"
    local decrypted_file="$TEST_DIR/test_basic.txt.decrypted"
    local original_content="This is a basic test file for encryption."
    
    if [ ! -f "$encrypted_file" ]; then
        log_warning "Encrypted file not found, skipping decryption test"
        record_test "Basic decryption" 1
        return
    fi
    
    # Run decryption
    log_info "Decrypting file..."
    local output
    output=$(run_encrypt "dec" "$encrypted_file" "$decrypted_file" "$TEST_PASSWORD")
    echo "$output"
    
    # Verify decrypted file
    if [ -f "$decrypted_file" ]; then
        log_verbose "Decrypted file created: $decrypted_file"
        log_verbose "Decrypted file size: $(wc -c < "$decrypted_file") bytes"
        
        local decrypted_content
        decrypted_content=$(cat "$decrypted_file")
        log_verbose "Decrypted content: $decrypted_content"
        
        if [ "$decrypted_content" = "$original_content" ]; then
            record_test "Decrypted content matches original" 0
        else
            log_verbose "Expected: $original_content"
            log_verbose "Got: $decrypted_content"
            record_test "Decrypted content matches original" 1
        fi
    else
        record_test "Basic decryption creates output file" 1
    fi
}

test_roundtrip_binary() {
    log_subheader "Test 3: Binary File Roundtrip"
    
    local test_file="$TEST_DIR/test_binary.bin"
    local encrypted_file="${test_file}.enc"
    local decrypted_file="$TEST_DIR/test_binary_decrypted.bin"
    
    # Create binary test file with random data
    dd if=/dev/urandom of="$test_file" bs=1024 count=10 2>/dev/null
    log_verbose "Created binary test file: $test_file"
    log_verbose "File size: $(wc -c < "$test_file") bytes"
    
    # Calculate original checksum
    local original_checksum
    original_checksum=$(sha256sum "$test_file" | cut -d' ' -f1)
    log_verbose "Original SHA256: $original_checksum"
    
    # Encrypt
    log_info "Encrypting binary file..."
    run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    
    # Decrypt
    log_info "Decrypting binary file..."
    run_encrypt "dec" "$encrypted_file" "$decrypted_file" "$TEST_PASSWORD" >/dev/null 2>&1
    
    # Verify checksum
    if [ -f "$decrypted_file" ]; then
        local decrypted_checksum
        decrypted_checksum=$(sha256sum "$decrypted_file" | cut -d' ' -f1)
        log_verbose "Decrypted SHA256: $decrypted_checksum"
        
        if [ "$original_checksum" = "$decrypted_checksum" ]; then
            record_test "Binary file roundtrip integrity (SHA256 match)" 0
        else
            record_test "Binary file roundtrip integrity (SHA256 match)" 1
        fi
    else
        record_test "Binary file roundtrip creates decrypted file" 1
    fi
}

test_large_file() {
    log_subheader "Test 4: Large File Handling"
    
    local test_file="$TEST_DIR/test_large.bin"
    local encrypted_file="${test_file}.enc"
    local decrypted_file="$TEST_DIR/test_large_decrypted.bin"
    
    # Create 5MB test file
    log_info "Creating 5MB test file..."
    dd if=/dev/urandom of="$test_file" bs=1M count=5 2>/dev/null
    log_verbose "File size: $(du -h "$test_file" | cut -f1)"
    
    local original_checksum
    original_checksum=$(sha256sum "$test_file" | cut -d' ' -f1)
    log_verbose "Original SHA256: $original_checksum"
    
    # Time encryption
    log_info "Encrypting large file (timing)..."
    local start_time end_time duration
    start_time=$(date +%s)
    run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_verbose "Encryption time: ${duration}s"
    log_verbose "Encrypted file size: $(du -h "$encrypted_file" | cut -f1)"
    
    # Time decryption
    log_info "Decrypting large file (timing)..."
    start_time=$(date +%s)
    run_encrypt "dec" "$encrypted_file" "$decrypted_file" "$TEST_PASSWORD" >/dev/null 2>&1
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_verbose "Decryption time: ${duration}s"
    
    # Verify
    if [ -f "$decrypted_file" ]; then
        local decrypted_checksum
        decrypted_checksum=$(sha256sum "$decrypted_file" | cut -d' ' -f1)
        
        if [ "$original_checksum" = "$decrypted_checksum" ]; then
            record_test "Large file (5MB) roundtrip integrity" 0
        else
            record_test "Large file (5MB) roundtrip integrity" 1
        fi
    else
        record_test "Large file roundtrip" 1
    fi
}

test_wrong_password() {
    log_subheader "Test 5: Wrong Password Detection"
    
    local test_file="$TEST_DIR/test_wrong_pw.txt"
    local encrypted_file="${test_file}.enc"
    local decrypted_file="$TEST_DIR/test_wrong_pw_decrypted.txt"
    
    # Create and encrypt test file
    echo "Secret data that should not be readable with wrong password" > "$test_file"
    run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    
    # Attempt decryption with wrong password
    log_info "Attempting decryption with wrong password..."
    local output
    output=$(run_encrypt "dec" "$encrypted_file" "$decrypted_file" "WrongPassword123!" 2>&1) || true
    echo "$output"
    
    # Decryption should fail or produce garbage
    if [[ "$output" == *"failed"* ]] || [[ "$output" == *"bad decrypt"* ]] || [ ! -s "$decrypted_file" ]; then
        record_test "Wrong password is rejected/fails" 0
    else
        # Check if content is garbage (not matching original)
        local decrypted_content original_content
        original_content=$(cat "$test_file")
        decrypted_content=$(cat "$decrypted_file" 2>/dev/null || echo "")
        if [ "$decrypted_content" != "$original_content" ]; then
            record_test "Wrong password produces different/garbage output" 0
        else
            record_test "Wrong password detection" 1
        fi
    fi
}

test_password_mismatch() {
    log_subheader "Test 6: Password Confirmation Mismatch"
    
    local test_file="$TEST_DIR/test_mismatch.txt"
    echo "Test content" > "$test_file"
    
    log_info "Testing password confirmation mismatch..."
    local output
    output=$(run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "DifferentPassword!" "n" 2>&1) || true
    echo "$output"
    
    if [[ "$output" == *"do not match"* ]]; then
        record_test "Password mismatch is detected" 0
    else
        record_test "Password mismatch is detected" 1
    fi
}

test_custom_output_path() {
    log_subheader "Test 7: Custom Output Path"
    
    local test_file="$TEST_DIR/test_custom.txt"
    local custom_enc="$TEST_DIR/custom_output.enc"
    local custom_dec="$TEST_DIR/custom_decrypted.txt"
    local test_content="Custom output path test"
    
    echo "$test_content" > "$test_file"
    
    # Encrypt to custom path
    log_info "Encrypting to custom output path..."
    run_encrypt "enc" "$test_file" "$custom_enc" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    
    if [ -f "$custom_enc" ]; then
        log_verbose "Custom encrypted file created: $custom_enc"
        record_test "Encryption to custom output path" 0
    else
        record_test "Encryption to custom output path" 1
        return
    fi
    
    # Decrypt from custom path
    log_info "Decrypting from custom path..."
    run_encrypt "dec" "$custom_enc" "$custom_dec" "$TEST_PASSWORD" >/dev/null 2>&1
    
    if [ -f "$custom_dec" ]; then
        local decrypted_content
        decrypted_content=$(cat "$custom_dec")
        if [ "$decrypted_content" = "$test_content" ]; then
            record_test "Decryption from custom path with integrity" 0
        else
            record_test "Decryption from custom path with integrity" 1
        fi
    else
        record_test "Decryption from custom path" 1
    fi
}

test_special_characters() {
    log_subheader "Test 8: Special Characters in Content"
    
    local test_file="$TEST_DIR/test_special.txt"
    local encrypted_file="${test_file}.enc"
    local decrypted_file="$TEST_DIR/test_special_decrypted.txt"
    
    # Content with special characters
    local test_content='Special chars: !@#$%^&*()_+-=[]{}|;:",.<>?/`~
Unicode: 日本語 中文 한국어 Ελληνικά العربية
Newlines and tabs:
	Tab here
    Spaces here
Backslashes: \n \t \r \\ 
Quotes: "double" and '\''single'\''
Null-like: \0 \x00'
    
    printf '%s' "$test_content" > "$test_file"
    log_verbose "Created test file with special characters"
    log_verbose "Original file size: $(wc -c < "$test_file") bytes"
    
    # Encrypt
    run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    
    # Decrypt
    run_encrypt "dec" "$encrypted_file" "$decrypted_file" "$TEST_PASSWORD" >/dev/null 2>&1
    
    if [ -f "$decrypted_file" ]; then
        # Compare byte-by-byte
        if cmp -s "$test_file" "$decrypted_file"; then
            record_test "Special characters preserved through roundtrip" 0
        else
            log_verbose "Files differ - showing diff:"
            diff "$test_file" "$decrypted_file" || true
            record_test "Special characters preserved through roundtrip" 1
        fi
    else
        record_test "Special characters test - decryption" 1
    fi
}

test_empty_file() {
    log_subheader "Test 9: Empty File Handling"
    
    local test_file="$TEST_DIR/test_empty.txt"
    local encrypted_file="${test_file}.enc"
    local decrypted_file="$TEST_DIR/test_empty_decrypted.txt"
    
    # Create empty file
    touch "$test_file"
    log_verbose "Created empty test file"
    
    # Encrypt
    log_info "Encrypting empty file..."
    run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    
    if [ -f "$encrypted_file" ]; then
        log_verbose "Encrypted empty file size: $(wc -c < "$encrypted_file") bytes"
        
        # Decrypt
        run_encrypt "dec" "$encrypted_file" "$decrypted_file" "$TEST_PASSWORD" >/dev/null 2>&1
        
        if [ -f "$decrypted_file" ] && [ ! -s "$decrypted_file" ]; then
            record_test "Empty file roundtrip" 0
        else
            record_test "Empty file roundtrip" 1
        fi
    else
        record_test "Empty file encryption" 1
    fi
}

test_file_not_found() {
    log_subheader "Test 10: Non-existent File Error Handling"
    
    log_info "Testing encryption of non-existent file..."
    local output
    output=$(run_encrypt "enc" "$TEST_DIR/nonexistent.txt" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" 2>&1) || true
    echo "$output"
    
    if [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"Error"* ]]; then
        record_test "Non-existent file error handling" 0
    else
        record_test "Non-existent file error handling" 1
    fi
}

test_openssl_header() {
    log_subheader "Test 11: OpenSSL File Format Verification"
    
    local test_file="$TEST_DIR/test_format.txt"
    local encrypted_file="${test_file}.enc"
    
    echo "Format verification test" > "$test_file"
    run_encrypt "enc" "$test_file" "" "$TEST_PASSWORD" "$TEST_PASSWORD" "n" >/dev/null 2>&1
    
    if [ -f "$encrypted_file" ]; then
        # Check for "Salted__" magic bytes (OpenSSL salted format)
        local header
        header=$(head -c 8 "$encrypted_file")
        if command -v xxd >/dev/null 2>&1; then
            log_verbose "File header (raw): $(xxd -l 8 "$encrypted_file" 2>/dev/null | head -1 || true)"
        elif command -v od >/dev/null 2>&1; then
            log_verbose "File header (raw): $(od -A x -t x1z -v -N 8 "$encrypted_file" 2>/dev/null || true)"
        fi
        
        if [[ "$header" == "Salted__" ]]; then
            log_verbose "Correct OpenSSL salted format detected"
            record_test "OpenSSL salted format header present" 0
        else
            log_verbose "Expected 'Salted__' header not found"
            record_test "OpenSSL salted format header present" 1
        fi
    else
        record_test "OpenSSL format verification" 1
    fi
}

# -----------------------------
# Main Test Runner
# -----------------------------
main() {
    log_header "ENCRYPT.SH TEST SUITE"
    echo -e "${BOLD}Test started at: $(date)${NC}"
    echo -e "${BOLD}Test password: ${TEST_PASSWORD}${NC}"
    
    # Setup
    setup
    
    # Run all tests
    test_basic_encryption
    test_basic_decryption
    test_roundtrip_binary
    test_large_file
    test_wrong_password
    test_password_mismatch
    test_custom_output_path
    test_special_characters
    test_empty_file
    test_file_not_found
    test_openssl_header
    
    # Summary
    log_header "TEST SUMMARY"
    echo -e "${BOLD}Total Tests:  ${TESTS_TOTAL}${NC}"
    echo -e "${GREEN}${BOLD}Passed:       ${TESTS_PASSED}${NC}"
    echo -e "${RED}${BOLD}Failed:       ${TESTS_FAILED}${NC}"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        cleanup
        exit 0
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        echo -e "${YELLOW}Test workspace preserved at: $TEST_DIR${NC}"
        exit 1
    fi
}

# Handle cleanup on interrupt (but not normal exit, handled in main)
trap 'cleanup; exit 130' INT TERM

# Run main
main "$@"
