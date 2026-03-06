# FileEnc-OpenSSL

A command-line utility for encrypting and decrypting files using OpenSSL with
password-based key derivation. Designed for local use, scripting, and automated
workflows where predictable behavior and explicit user confirmation are required.

---

## Features

- File encryption and decryption using OpenSSL
- AES-256-CBC cipher
- PBKDF2 key derivation with configurable iteration count
- Secure password input (no terminal echo)
- Optional secure deletion of plaintext after encryption
- Deterministic file naming defaults
- Supports text and binary files
- No external configuration files

---

## Installation

Clone the repository and run the setup script:

```sh
./setup.sh
````

This installs a symbolic link named `encrypt` into a directory already present
in the user’s `PATH` (preferring `~/.local/bin` when available).

No shell configuration files are modified.

---

## Usage

### Encrypt a file

```bash
encrypt enc -i INPUT_FILE
```

Creates an encrypted file named:

```
INPUT_FILE.enc
```

The user is prompted to:

* enter a password
* confirm the password
* optionally shred the original plaintext file

---

### Decrypt a file

```sh
encrypt dec -i INPUT_FILE.enc
```

Creates a decrypted file with the `.enc` suffix removed.

---

### Custom output path

```sh
encrypt enc -i file.txt -o encrypted.bin
encrypt dec -i encrypted.bin -o recovered.txt
```

---

## Command Syntax

```text
encrypt enc -i INPUT_FILE [-o OUTPUT_FILE]
encrypt dec -i INPUT_FILE [-o OUTPUT_FILE]
```

### Options

| Option           | Description                 |
| ---------------- | --------------------------- |
| `enc`, `encrypt` | Encrypt input file          |
| `dec`, `decrypt` | Decrypt input file          |
| `-i`             | Input file path (required)  |
| `-o`             | Output file path (optional) |

---

## Cryptographic Parameters

* Cipher: `AES-256-CBC`
* Key derivation: `PBKDF2`
* Iterations: `100000` (can be increaded though should be fine)
* Salt: enabled (OpenSSL salted format)

These parameters balance compatibility and resistance to offline brute-force
attacks.

---

## Secure Deletion

After successful encryption, the tool can optionally overwrite and remove the
original plaintext file using `shred`.

Behavior:

* Multiple overwrite passes
* File removal after overwrite

Limitations:

* Not reliable on SSD/NVMe devices
* Not reliable on copy-on-write filesystems
* Does not affect filesystem snapshots or backups

Secure deletion is best-effort and should not be considered a forensic guarantee.

---

## Non-interactive Use

Passwords may be supplied via standard input:
- I highly reccomend against this as a simple `history` command would then reveal your encryption password.

```sh
printf '%s\n%s\nn\n' "password" "password" | encrypt enc -i file.txt
```

This mode is suitable for automation but should be used cautiously.

---

## Testing

A comprehensive test suite is included:

```sh
cd tests
chmod +x test.sh
./test.sh
```

The tests verify:

* encryption and decryption correctness
* binary and large file handling
* incorrect password behavior
* edge cases (empty files, special characters)
* OpenSSL file format integrity

---

## Uninstallation

Remove the installed symlink:

```sh
rm ~/.local/bin/encrypt
```

or, if installed system-wide:

```sh
sudo rm /usr/local/bin/encrypt
```

No other files are modified.

---

## Scope and Threat Model

This tool is intended for:

* local file protection
* scripting and automation
* secure storage workflows

It does not protect against:

* compromised operating systems
* malicious privileged users
* recovery from filesystem-level snapshots

For stronger guarantees, use full-disk encryption or key-destruction-based
workflows. I don't reccomend this for use in secure environments in the slightest though it's good nuff' for me.

---

##### TODO

- detached signature support
- AEAD (AES-GCM) option
- More ciphers
- SSH key support
- GPG support (make it simple to use pre-existing `gpg` tool.
- Hybrid-encryption
- PQC ciphers (Digital signatures, KEM, encryption etc.)
