# Smallest SPCS Container

The world's smallest container for Snowflake Snowpark Container Services - a **112-byte** hand-crafted x86-64 ELF binary that prints "Hello, Snowflake" and exits.

## Why 112 Bytes?

This is the theoretical minimum for a 64-bit ELF on native Linux:

| Component | Size |
|-----------|------|
| ELF Header | 64 bytes |
| Program Header | 56 bytes |
| Header Overlap | -8 bytes |
| **Total** | **112 bytes** |

All executable code is embedded within the headers themselves.

## Quick Start

```bash
# Create infrastructure
snow object create database name=TINY_SPCS --if-not-exists -c spcs
snow object create schema name=TINY_112_BYTES --database TINY_SPCS --if-not-exists -c spcs
snow spcs compute-pool create TINY_POOL --min-nodes 1 --max-nodes 1 --family CPU_X64_XS -c spcs
snow spcs image-repository create IMAGES --database TINY_SPCS --schema TINY_112_BYTES -c spcs

# Build and push (replace YOUR_ACCOUNT with your account locator)
docker build --platform linux/amd64 -t smallest_spcs:112bytes .
snow spcs image-registry login -c spcs
docker tag smallest_spcs:112bytes YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes
docker push YOUR_ACCOUNT.registry.snowflakecomputing.com/tiny_spcs/tiny_112_bytes/images/smallest_spcs:112bytes

# Run and verify
snow spcs service execute-job TINY_JOB --compute-pool TINY_POOL --spec-path tiny_spec.yaml --database TINY_SPCS --schema TINY_112_BYTES -c spcs
snow spcs service logs TINY_JOB --container-name hello --instance-id 0 --database TINY_SPCS --schema TINY_112_BYTES -c spcs
# Output: Hello, Snowflake
```

## Files

| File | Description |
|------|-------------|
| `hello_snowflake_64_112` | 112-byte binary for SPCS (native Linux) |
| `hello_snowflake_64_rosetta` | 141-byte binary for Docker on Mac |
| `Dockerfile` | Scratch-based container |
| `tiny_spec.yaml` | SPCS job specification |

## Documentation

See [SPCS_DEPLOYMENT_GUIDE.md](SPCS_DEPLOYMENT_GUIDE.md) for:
- Snowflake trial account setup with screenshots
- Snow CLI installation and PAT configuration
- Step-by-step deployment (11 steps)
- Troubleshooting guide
- Claude Code automation (run the entire guide with AI)

## License

MIT
