# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project demonstrates deploying the world's smallest possible 64-bit Linux ELF binary (112 bytes) to Snowflake Snowpark Container Services (SPCS). The binary prints "Hello, Snowflake" and exits successfully.

## Key Files

| File | Size | Purpose |
|------|------|---------|
| `hello_snowflake_64_112` | 112 bytes | Production binary for SPCS (native Linux only) |
| `hello_snowflake_64_rosetta` | 141 bytes | Testing binary for Docker on Mac (Apple Silicon) |
| `*.asm` | - | NASM assembly source files |
| `Dockerfile` | - | Scratch-based container (copies 112-byte binary) |
| `tiny_spec.yaml` | - | SPCS service specification |

## Build Commands

```bash
# Build 112-byte binary (native Linux)
nasm -f bin -o hello_snowflake_64_112 hello_snowflake_64_112.asm
chmod +x hello_snowflake_64_112

# Build 141-byte Rosetta-compatible binary
nasm -f bin -o hello_snowflake_64_rosetta hello_snowflake_64_rosetta.asm
chmod +x hello_snowflake_64_rosetta

# Build Docker image
docker build --platform linux/amd64 -t smallest_spcs:112bytes .
```

## Testing

```bash
# Test on native Linux
./hello_snowflake_64_112

# Test on macOS (Apple Silicon) - use Rosetta version
docker run --rm --platform linux/amd64 \
  -v "$(pwd):/work" -w /work \
  debian:bookworm-slim \
  sh -c './hello_snowflake_64_rosetta; echo "Exit: $?"'

# Build via Docker (if no local NASM)
docker run --rm --platform linux/amd64 \
  -v "$(pwd):/work" -w /work \
  debian:bookworm-slim \
  sh -c 'apt-get update -qq && apt-get install -qq -y nasm > /dev/null && \
         nasm -f bin -o hello_snowflake_64_112 hello_snowflake_64_112.asm && \
         chmod +x hello_snowflake_64_112'
```

## Why Two Binaries

The 112-byte binary uses extreme ELF header abuse (code embedded in e_ident, e_version, e_shoff, e_flags fields) that works on native Linux but fails on QEMU/Rosetta emulation. The 141-byte version uses only compatible tricks (header overlap, strings in p_paddr/p_align).

## SPCS Deployment

Uses Snowflake CLI (`snow`) with connection profile `spcs`:

```bash
# Deploy to SPCS
snow spcs service create TINY_JOB \
  --spec-path tiny_spec.yaml \
  --compute-pool TINY_POOL \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs

# Check status
snow spcs service status TINY_JOB \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

See `SPCS_DEPLOYMENT_GUIDE.md` for complete infrastructure setup.
