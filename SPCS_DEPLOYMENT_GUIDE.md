# Deploying the World's Smallest Container to Snowflake SPCS

This guide walks you through deploying a **112-byte executable** to Snowflake Snowpark Container Services (SPCS). This is the smallest possible 64-bit Linux ELF binary that prints "Hello, Snowflake" and exits successfully.

## Overview

| Component | Size | Notes |
|-----------|------|-------|
| ELF Binary (Native Linux) | 112 bytes | For SPCS and native x86-64 Linux |
| ELF Binary (Rosetta/QEMU) | 141 bytes | For Docker on Mac (Apple Silicon) |
| Docker Image | ~112-141 bytes | Scratch base |
| Output | "Hello, Snowflake" | |

---

## Two Versions: Native vs Rosetta

This project includes **two binaries** that produce identical output:

| Binary | Size | Use Case |
|--------|------|----------|
| `hello_snowflake_64_112` | 112 bytes | **SPCS deployment**, native Linux x86-64 |
| `hello_snowflake_64_rosetta` | 141 bytes | **Local testing** on Docker for Mac (Apple Silicon) |

**Why two versions?** The 112-byte binary uses extreme header abuse tricks that work on native Linux but fail on QEMU/Rosetta emulation used by Docker on Mac. The 141-byte version uses compatible tricks.

---

## Why 112 Bytes is the Theoretical Minimum

For a **64-bit ELF on native modern Linux** (kernel 6.x), 112 bytes is the absolute minimum:

| Component | Size |
|-----------|------|
| ELF Header | 64 bytes |
| Program Header | 56 bytes |
| Header Overlap | -8 bytes |
| **Total** | **112 bytes** |

The math is simple:
- ELF header is exactly 64 bytes (fixed by spec)
- Program header is exactly 56 bytes for 64-bit ELF
- Maximum overlap is 8 bytes (program header starts at byte 56)
- **64 + 56 - 8 = 112 bytes**

All executable code is embedded within the headers themselves - there is literally no room for further reduction on 64-bit Linux.

> **Note**: Smaller 64-bit ELFs (89 bytes) exist for QEMU user-mode emulation, and 32-bit ELFs can be as small as 76 bytes, but for native 64-bit Linux containers, 112 bytes is the floor.

---

## Prerequisites

- Snowflake account with ACCOUNTADMIN access
- [Snowflake CLI (`snow`)](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) installed
- Docker installed and running
- The 112-byte binary: `hello_snowflake_64_112`

---

## Step 1: Configure Snowflake CLI

### 1.1 Create a Programmatic Access Token (PAT)

1. Log into Snowsight
2. Go to **Admin** → **Security** → **Programmatic Access Tokens**
3. Click **+ Programmatic Access Token**
4. Name it (e.g., "spcs-deploy") and set expiration
5. Copy the token and save it to a file:

```bash
echo "YOUR_TOKEN_HERE" > pat-token.txt
chmod 600 pat-token.txt
```

### 1.2 Configure the CLI Connection

Edit `~/.config/snowflake/config.toml`:

```toml
[connections.spcs]
account = "YOUR_ACCOUNT_LOCATOR"
user = "YOUR_USERNAME"
host = "YOUR_ACCOUNT_LOCATOR.snowflakecomputing.com"
authenticator = "PROGRAMMATIC_ACCESS_TOKEN"
token_file_path = "/path/to/pat-token.txt"
```

### 1.3 Test the Connection

```bash
snow sql -c spcs -q "SELECT CURRENT_USER(), CURRENT_ACCOUNT();"
```

---

## Step 2: Create Snowflake Infrastructure

### 2.1 Create Database and Schema

```sql
-- Create database for the project
CREATE DATABASE IF NOT EXISTS TINY_SPCS;

-- Create schema for the 112-byte binary
CREATE SCHEMA IF NOT EXISTS TINY_SPCS.TINY_112_BYTES;
```

Using the CLI:

```bash
snow sql -c spcs -q "CREATE DATABASE IF NOT EXISTS TINY_SPCS;"
snow sql -c spcs -q "CREATE SCHEMA IF NOT EXISTS TINY_SPCS.TINY_112_BYTES;"
```

### 2.2 Create Compute Pool

The compute pool provides the infrastructure to run containers:

```sql
CREATE COMPUTE POOL IF NOT EXISTS TINY_POOL
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_SUSPEND_SECS = 300;
```

Using the CLI:

```bash
snow spcs compute-pool create TINY_POOL \
  --min-nodes 1 \
  --max-nodes 1 \
  --family CPU_X64_XS \
  --auto-suspend-secs 300 \
  -c spcs
```

Wait for the compute pool to be ready:

```bash
snow spcs compute-pool status TINY_POOL -c spcs
```

The pool is ready when status shows `ACTIVE` or `IDLE`.

### 2.3 Create Image Repository

```sql
CREATE IMAGE REPOSITORY IF NOT EXISTS TINY_SPCS.TINY_112_BYTES.IMAGES;
```

Using the CLI:

```bash
snow spcs image-repository create IMAGES \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

Get the repository URL:

```bash
snow spcs image-repository url IMAGES \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

This returns something like:
```
YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images
```

---

## Step 3: Build and Push Docker Image

### 3.1 Create the Dockerfile

Create a `Dockerfile` in the same directory as the binary:

```dockerfile
# Minimal Docker image - scratch (empty) with 112-byte ELF
# For Snowflake Snowpark Container Services (SPCS)

FROM scratch

# Copy the 112-byte binary
COPY hello_snowflake_64_112 /hello_snowflake

# Run the binary - prints "Hello, Snowflake" and exits 0
CMD ["/hello_snowflake"]
```

### 3.2 Build the Image

```bash
docker build --platform linux/amd64 -t smallest_spcs:112bytes .
```

Verify the image size:

```bash
docker images smallest_spcs:112bytes
```

Expected output shows ~112 bytes (displayed as 112B or similar).

### 3.3 Test Locally

Before pushing to Snowflake, verify the container works.

**On Native Linux (x86-64):**

```bash
docker run --rm smallest_spcs:112bytes
```

**On macOS (Apple Silicon) - Use the Rosetta version for local testing:**

The 112-byte binary uses header tricks that don't work in Docker's QEMU/Rosetta emulation. For local testing on Mac, use the 141-byte Rosetta-compatible version:

```bash
# Test the Rosetta version locally
docker run --rm --platform linux/amd64 \
  -v "$(pwd):/work" -w /work \
  debian:bookworm-slim \
  sh -c './hello_snowflake_64_rosetta; echo "Exit: $?"'
```

> **Note**: The 112-byte version WILL work when deployed to SPCS (which runs on native Linux). The Rosetta version is only needed for local Docker testing on Mac.

Expected output:

```
Hello, Snowflake
Exit: 0
```

### 3.4 Tag for Snowflake Registry

Replace `YOUR_ACCOUNT` with your account locator:

```bash
docker tag smallest_spcs:112bytes \
  YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes
```

### 3.5 Authenticate to Snowflake Registry

```bash
snow spcs image-registry login -c spcs
```

### 3.6 Push the Image

```bash
docker push \
  YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes
```

Verify the image was pushed:

```bash
snow spcs image-repository list-images IMAGES \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

---

## Step 4: Set Up Event Table for Logging

### 4.1 Create Event Table

```sql
CREATE EVENT TABLE IF NOT EXISTS TINY_SPCS.TINY_112_BYTES.EVENTS;
```

### 4.2 Associate Event Table with Database

```sql
ALTER DATABASE TINY_SPCS SET EVENT_TABLE = TINY_SPCS.TINY_112_BYTES.EVENTS;
ALTER DATABASE TINY_SPCS SET LOG_LEVEL = 'INFO';
```

Using the CLI:

```bash
snow sql -c spcs -q "CREATE EVENT TABLE IF NOT EXISTS TINY_SPCS.TINY_112_BYTES.EVENTS;"
snow sql -c spcs -q "ALTER DATABASE TINY_SPCS SET EVENT_TABLE = TINY_SPCS.TINY_112_BYTES.EVENTS;"
snow sql -c spcs -q "ALTER DATABASE TINY_SPCS SET LOG_LEVEL = 'INFO';"
```

---

## Step 5: Create and Run the Job

### 5.1 Create Service Specification

Create `tiny_spec.yaml`:

```yaml
spec:
  containers:
    - name: hello
      image: /tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes
```

### 5.2 Create the Job Service

```bash
snow spcs service create TINY_JOB \
  --spec-path tiny_spec.yaml \
  --compute-pool TINY_POOL \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

### 5.3 Check Job Status

```bash
snow spcs service status TINY_JOB \
  --database TINY_SPCS \
  --schema TINY_112_BYTES \
  -c spcs
```

Expected output shows:
- **status**: DONE
- **message**: Completed successfully
- **lastExitCode**: 0

---

## Step 6: Verify the Output

### 6.1 Query the Event Table

```sql
SELECT
  TIMESTAMP,
  RECORD_TYPE,
  VALUE
FROM TINY_SPCS.TINY_112_BYTES.EVENTS
WHERE RECORD_TYPE = 'LOG'
ORDER BY TIMESTAMP DESC
LIMIT 10;
```

Using the CLI:

```bash
snow sql -c spcs -q "
  SELECT TIMESTAMP, RECORD_TYPE, VALUE
  FROM TINY_SPCS.TINY_112_BYTES.EVENTS
  WHERE RECORD_TYPE = 'LOG'
  ORDER BY TIMESTAMP DESC
  LIMIT 10;
"
```

Expected output:

| TIMESTAMP | RECORD_TYPE | VALUE |
|-----------|-------------|-------|
| 2026-01-04 21:06:09 | LOG | "Hello, Snowflake" |

### 6.2 View All Events (Optional)

```sql
SELECT
  TIMESTAMP,
  RECORD_TYPE,
  VALUE
FROM TINY_SPCS.TINY_112_BYTES.EVENTS
ORDER BY TIMESTAMP DESC
LIMIT 20;
```

This shows the complete job lifecycle:
- `PENDING` - Job waiting to start
- `READY` - Container running
- `LOG` - "Hello, Snowflake" output
- `DONE` - Completed successfully

---

## Cleanup

To remove all resources created by this guide:

```sql
-- Drop the job service
DROP SERVICE IF EXISTS TINY_SPCS.TINY_112_BYTES.TINY_JOB;

-- Drop the compute pool (may take a minute)
DROP COMPUTE POOL IF EXISTS TINY_POOL;

-- Drop the database (includes schema, event table, image repository)
DROP DATABASE IF EXISTS TINY_SPCS;
```

Using the CLI:

```bash
snow spcs service drop TINY_JOB --database TINY_SPCS --schema TINY_112_BYTES -c spcs
snow spcs compute-pool drop TINY_POOL -c spcs
snow sql -c spcs -q "DROP DATABASE IF EXISTS TINY_SPCS;"
```

---

## Quick Reference

### All Commands in Order

```bash
# 1. Create infrastructure
snow sql -c spcs -q "CREATE DATABASE IF NOT EXISTS TINY_SPCS;"
snow sql -c spcs -q "CREATE SCHEMA IF NOT EXISTS TINY_SPCS.TINY_112_BYTES;"
snow spcs compute-pool create TINY_POOL --min-nodes 1 --max-nodes 1 --family CPU_X64_XS -c spcs
snow spcs image-repository create IMAGES --database TINY_SPCS --schema TINY_112_BYTES -c spcs

# 2. Build, test locally, and push image
docker build --platform linux/amd64 -t smallest_spcs:112bytes .
docker run --rm --platform linux/amd64 smallest_spcs:112bytes  # Should print "Hello, Snowflake"
docker tag smallest_spcs:112bytes YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes
snow spcs image-registry login -c spcs
docker push YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes

# 3. Set up logging
snow sql -c spcs -q "CREATE EVENT TABLE IF NOT EXISTS TINY_SPCS.TINY_112_BYTES.EVENTS;"
snow sql -c spcs -q "ALTER DATABASE TINY_SPCS SET EVENT_TABLE = TINY_SPCS.TINY_112_BYTES.EVENTS;"
snow sql -c spcs -q "ALTER DATABASE TINY_SPCS SET LOG_LEVEL = 'INFO';"

# 4. Run the job
snow spcs service create TINY_JOB --spec-path tiny_spec.yaml --compute-pool TINY_POOL --database TINY_SPCS --schema TINY_112_BYTES -c spcs

# 5. Verify
snow spcs service status TINY_JOB --database TINY_SPCS --schema TINY_112_BYTES -c spcs
snow sql -c spcs -q "SELECT TIMESTAMP, VALUE FROM TINY_SPCS.TINY_112_BYTES.EVENTS WHERE RECORD_TYPE = 'LOG' ORDER BY TIMESTAMP DESC LIMIT 5;"
```

---

## About the 112-Byte Binary

The `hello_snowflake_64_112` binary is a hand-crafted x86-64 ELF executable that:

- Uses only 112 bytes (the theoretical minimum for a 64-bit ELF that prints output)
- Prints "Hello, Snowflake" to stdout
- Exits with code 0
- Runs on any modern Linux kernel (5.x+)

### Assembly Source Code

```nasm
; hello_snowflake_64_112.asm - 112-byte "Hello, Snowflake" ELF
; Build: nasm -f bin -o hello_snowflake_64_112 hello_snowflake_64_112.asm && chmod +x hello_snowflake_64_112

BITS 64
base equ 0x10000
ORG base

ehdr:
    db 0x7f, "ELF"
    db 2, 1, 1, 0           ; 64-bit, little-endian, ELF v1

frag1:                      ; e_ident[8-15] - Entry point!
    syscall                 ; Sets rcx = return address (0x1000a)
    pop rdi                 ; rdi = argc = 1 (stdout fd)
    push rcx                ; Push newline char (0x0a from rcx low byte)
    mov eax, edi            ; rax = 1 (write syscall)
    jmp short frag2

    dw 2                    ; e_type = ET_EXEC
    dw 0x3e                 ; e_machine = x86-64

exit_code:                  ; e_version - reused for exit code!
    mov al, 1               ; 32-bit exit syscall = 1
    int 0x80                ; exit(ebx) - ebx = 0 from kernel init

    dq frag1                ; e_entry - points to frag1
    dq phdr - ehdr          ; e_phoff = 56

frag2:                      ; e_shoff - reused for code!
    push qword [rcx + 0x5e] ; Push "nowflake" from p_align
    push qword [rcx + 0x46] ; Push "Hello, S" from p_paddr
    mov dl, 17              ; Length = 17 (16 chars + newline)

frag3:                      ; e_flags - reused for write syscall!
    push rsp
    pop rsi                 ; rsi = stack pointer (message)
    syscall                 ; write(1, "Hello, Snowflake\n", 17)

    dw 0xdeeb               ; e_ehsize = jmp -34 (back to exit_code)
    dw 56                   ; e_phentsize = 56

phdr:                       ; Program header (overlaps last 8 bytes of ELF header)
    dd 1                    ; p_type = PT_LOAD
    dd 5                    ; p_flags = PF_R | PF_X
    dq 0                    ; p_offset = 0
    dq base                 ; p_vaddr = 0x10000
    db "Hello, S"           ; p_paddr - string part 1!
    dq file_end - ehdr      ; p_filesz = 112
    dq file_end - ehdr      ; p_memsz = 112
    db "nowflake"           ; p_align - string part 2!

file_end:
; Total: 112 bytes (0x70)
```

### Size Reduction Techniques

The binary achieves 112 bytes through extreme header abuse:

| Technique | Description |
|-----------|-------------|
| **Header overlap** | Program header starts at byte 56, overlapping 8 bytes with ELF header |
| **Code in e_ident[8-15]** | Entry point code in padding bytes (Linux ignores bytes 8-15) |
| **Code in e_version** | Exit code stored in version field (not validated) |
| **Code in e_shoff** | String construction code in section header offset (no sections) |
| **Code in e_flags** | Write syscall in flags field (x86-64 ignores flags) |
| **Jump in e_ehsize** | Backward jump encoded as "header size" (not validated) |
| **String in p_paddr** | "Hello, S" in physical address (Linux ignores p_paddr) |
| **String in p_align** | "nowflake" in alignment field (any alignment accepted) |
| **syscall rcx trick** | After syscall, rcx holds RIP; low byte 0x0a = newline character |
| **argc as fd** | Pop argc (1) from stack as stdout file descriptor |
| **int 0x80 exit** | 32-bit syscall in 64-bit mode; ebx=0 from kernel → exit(0) |

---

## Building From Source

### Native Linux

If you're on a Linux system with NASM installed:

```bash
# Install NASM (if not already installed)
sudo apt install nasm    # Debian/Ubuntu
sudo dnf install nasm    # Fedora/RHEL

# Save the assembly source to a file
cat > hello_snowflake_64_112.asm << 'EOF'
; hello_snowflake_64_112.asm - 112-byte "Hello, Snowflake" ELF
BITS 64
base equ 0x10000
ORG base

ehdr:
    db 0x7f, "ELF"
    db 2, 1, 1, 0

frag1:
    syscall
    pop rdi
    push rcx
    mov eax, edi
    jmp short frag2

    dw 2
    dw 0x3e

exit_code:
    mov al, 1
    int 0x80

    dq frag1
    dq phdr - ehdr

frag2:
    push qword [rcx + 0x5e]
    push qword [rcx + 0x46]
    mov dl, 17

frag3:
    push rsp
    pop rsi
    syscall

    dw 0xdeeb
    dw 56

phdr:
    dd 1
    dd 5
    dq 0
    dq base
    db "Hello, S"
    dq file_end - ehdr
    dq file_end - ehdr
    db "nowflake"

file_end:
EOF

# Compile
nasm -f bin -o hello_snowflake_64_112 hello_snowflake_64_112.asm

# Make executable
chmod +x hello_snowflake_64_112

# Verify size (should be exactly 112 bytes)
ls -l hello_snowflake_64_112

# Run
./hello_snowflake_64_112
```

Expected output:

```
Hello, Snowflake
```

### Using Docker (macOS/Windows)

If you're on macOS or Windows (or prefer not to install NASM locally):

```bash
# Save the assembly source to a file first (same as above)
cat > hello_snowflake_64_112.asm << 'EOF'
BITS 64
base equ 0x10000
ORG base

ehdr:
    db 0x7f, "ELF"
    db 2, 1, 1, 0

frag1:
    syscall
    pop rdi
    push rcx
    mov eax, edi
    jmp short frag2

    dw 2
    dw 0x3e

exit_code:
    mov al, 1
    int 0x80

    dq frag1
    dq phdr - ehdr

frag2:
    push qword [rcx + 0x5e]
    push qword [rcx + 0x46]
    mov dl, 17

frag3:
    push rsp
    pop rsi
    syscall

    dw 0xdeeb
    dw 56

phdr:
    dd 1
    dd 5
    dq 0
    dq base
    db "Hello, S"
    dq file_end - ehdr
    dq file_end - ehdr
    db "nowflake"

file_end:
EOF

# Compile and run in one Docker command
docker run --rm --platform linux/amd64 \
  -v "$(pwd):/work" -w /work \
  debian:bookworm-slim \
  sh -c 'apt-get update -qq && apt-get install -qq -y nasm > /dev/null && \
         nasm -f bin -o hello_snowflake_64_112 hello_snowflake_64_112.asm && \
         chmod +x hello_snowflake_64_112 && \
         ls -l hello_snowflake_64_112 && \
         ./hello_snowflake_64_112'
```

Expected output:

```
-rwxr-xr-x 1 root root 112 Jan  4 12:00 hello_snowflake_64_112
Hello, Snowflake
```

### Quick Docker Test (Pre-built Binary)

If you already have the binary and just want to test it:

```bash
docker run --rm --platform linux/amd64 \
  -v "$(pwd):/work" -w /work \
  debian:bookworm-slim \
  sh -c './hello_snowflake_64_112 ; echo "Exit code: $?"'
```

Expected output:

```
Hello, Snowflake
Exit code: 0
```

---

## Troubleshooting

### "Exec format error" on Docker for Mac

If you see this error when testing locally on macOS (especially Apple Silicon):

```
exec /hello_snowflake: exec format error
```

**This is expected!** The 112-byte binary uses header tricks that QEMU/Rosetta doesn't support. Solutions:

1. **For local testing**: Use the 141-byte Rosetta version:
   ```bash
   docker run --rm --platform linux/amd64 \
     -v "$(pwd):/work" -w /work \
     debian:bookworm-slim \
     sh -c './hello_snowflake_64_rosetta; echo "Exit: $?"'
   ```

2. **For SPCS deployment**: The 112-byte version WILL work on SPCS (native Linux). Deploy it directly without local testing.

### Compute Pool Not Starting

Check the pool status:
```bash
snow spcs compute-pool status TINY_POOL -c spcs
```

If stuck in `STARTING`, wait a few minutes. If `FAILED`, check your account's compute pool quota.

### Image Push Fails

1. Ensure you're logged in: `snow spcs image-registry login -c spcs`
2. Verify the repository exists: `snow spcs image-repository list --database TINY_SPCS --schema TINY_112_BYTES -c spcs`
3. Check the image tag matches the repository URL exactly

### No Logs in Event Table

1. Verify event table is set:
   ```sql
   SHOW PARAMETERS LIKE 'EVENT_TABLE' IN DATABASE TINY_SPCS;
   ```
2. Verify log level:
   ```sql
   SHOW PARAMETERS LIKE 'LOG_LEVEL' IN DATABASE TINY_SPCS;
   ```
3. Re-run the job after setting parameters

### Job Shows Exit Code != 0

The binary requires a 64-bit Linux environment. Ensure:
- Docker image was built with `--platform linux/amd64`
- The binary has execute permissions (`chmod +x hello_snowflake_64_112`)

---

## The 141-Byte Rosetta Version

For testing on Docker for Mac (Apple Silicon), a 141-byte version is provided that works with QEMU/Rosetta emulation.

### Why 141 Bytes Instead of 112?

QEMU/Rosetta has stricter ELF validation than native Linux:

| Check | Native Linux | QEMU/Rosetta |
|-------|--------------|--------------|
| Code in e_ident[8-15] | ✓ Ignored | ✗ Rejected |
| Code in e_version | ✓ Ignored | ✗ Validated |
| Code in e_shoff | ✓ Ignored | ✗ Validated |
| Code in e_flags | ✓ Ignored | ✗ Validated |
| e_ehsize = jump instruction | ✓ Ignored | ✗ Validated |
| int 0x80 (32-bit exit) | ✓ Works | ✗ Segfaults |

The 29-byte difference is exactly the code that must be moved from header fields to after the headers.

### Shared Tricks (Work on Both)

| Trick | Description |
|-------|-------------|
| 8-byte header overlap | Program header at offset 56 |
| String in p_paddr | "Hello, S" stored in unused field |
| String in p_align | "nowflake" stored in alignment field |
| Stack-constructed string | Push parts, use stack as buffer |
| argc as stdout fd | Pop argc (1) as file descriptor |

### Rosetta Assembly Source

```nasm
; hello_snowflake_64_rosetta.asm - 141-byte "Hello, Snowflake" for QEMU/Rosetta
BITS 64
base equ 0x10000
ORG base

ehdr:
    db 0x7f, "ELF"
    db 2, 1, 1, 0           ; 64-bit, little-endian, ELF v1
    dq 0                    ; e_ident[8-15] padding (can't use for code)

    dw 2                    ; e_type = ET_EXEC
    dw 0x3e                 ; e_machine = x86-64
    dd 1                    ; e_version = 1 (must be valid)

    dq code                 ; e_entry - points to code after headers
    dq 56                   ; e_phoff = 56 (8-byte overlap)

    dq 0                    ; e_shoff = 0 (must be valid)
    dd 0                    ; e_flags = 0 (must be valid)
    dw 64                   ; e_ehsize = 64 (must be valid)
    dw 56                   ; e_phentsize = 56

phdr:                       ; Offset 56: 8-byte overlap zone
    dd 1                    ; p_type = PT_LOAD / e_phnum = 1
    dd 5                    ; p_flags = R|X

    dq 0                    ; p_offset = 0
    dq base                 ; p_vaddr
str1:
    db "Hello, S"           ; p_paddr = first 8 chars
    dq filesize             ; p_filesz
    dq filesize             ; p_memsz
str2:
    db "nowflake"           ; p_align = last 8 chars

code:                       ; Offset 112: CODE (29 bytes)
    pop     rdi             ; argc = 1 (stdout fd)
    push    0x0a            ; newline
    mov     eax, str1       ; load str1 address
    push    qword [rax+24]  ; push "nowflake"
    push    qword [rax]     ; push "Hello, S"
    mov     eax, edi        ; rax = 1 (sys_write)
    push    rsp
    pop     rsi             ; rsi = stack buffer
    push    17
    pop     rdx             ; rdx = 17
    syscall                 ; write(1, buf, 17)
    push    60
    pop     rax             ; rax = 60 (sys_exit)
    xor     edi, edi        ; rdi = 0
    syscall                 ; exit(0)

filesize equ $ - $$
; Total: 141 bytes
```

### Building the Rosetta Version

```bash
nasm -f bin -o hello_snowflake_64_rosetta hello_snowflake_64_rosetta.asm
chmod +x hello_snowflake_64_rosetta
```

### Testing Both Versions

```bash
# On native Linux - both work
./hello_snowflake_64_112      # 112 bytes
./hello_snowflake_64_rosetta  # 141 bytes

# On Docker for Mac - only Rosetta version works locally
docker run --rm --platform linux/amd64 \
  -v "$(pwd):/work" -w /work \
  debian:bookworm-slim \
  sh -c './hello_snowflake_64_rosetta; echo "Exit: $?"'
```
