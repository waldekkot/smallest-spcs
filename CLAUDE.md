# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project demonstrates deploying the world's smallest possible 64-bit Linux ELF binary (112 bytes) to Snowflake Snowpark Container Services (SPCS). The binary prints "Hello, Snowflake" and exits successfully.

## Commit Convention

- Prefix documentation commits with `[docs]`
- Example: `[docs] Update deployment guide`

## Key Files

| File | Purpose |
|------|---------|
| `hello_snowflake_64_112` | 112-byte production binary for SPCS (native Linux only) |
| `hello_snowflake_64_rosetta` | 141-byte testing binary for Docker on Mac (Apple Silicon) |
| `*.asm` | NASM assembly source files |
| `Dockerfile` | Scratch-based container (copies 112-byte binary) |
| `tiny_spec.yaml` | SPCS service specification |
| `.env-token` | PAT token file (gitignored) |
| `SPCS_DEPLOYMENT_GUIDE.md` | Complete setup and deployment guide |

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

Uses Snowflake CLI (`snow`) with connection profile `spcs`.

### Create Infrastructure

```bash
snow object create database name=TINY_SPCS --if-not-exists -c spcs
snow object create schema name=TINY_112_BYTES --database TINY_SPCS --if-not-exists -c spcs
snow spcs compute-pool create TINY_POOL --min-nodes 1 --max-nodes 1 --family CPU_X64_XS --auto-suspend-secs 300 -c spcs
snow spcs image-repository create IMAGES --database TINY_SPCS --schema TINY_112_BYTES -c spcs
```

### Run Job

```bash
# Execute job (waits for completion)
snow spcs service execute-job TINY_JOB \
  --compute-pool TINY_POOL \
  --spec-path tiny_spec.yaml \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs

# View output
snow spcs service logs TINY_JOB \
  --container-name hello \
  --instance-id 0 \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

### Cleanup

```bash
snow spcs service drop TINY_JOB --database TINY_SPCS --schema TINY_112_BYTES -c spcs
snow spcs compute-pool drop TINY_POOL -c spcs
snow object drop database TINY_SPCS -c spcs
```

See `SPCS_DEPLOYMENT_GUIDE.md` for complete setup including trial account creation, CLI installation, and PAT configuration.
