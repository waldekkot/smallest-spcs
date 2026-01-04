# Minimal Docker image - scratch (empty) with 112-byte ELF
# For Snowflake Snowpark Container Services (SPCS)

FROM scratch

# Copy the 112-byte binary
COPY hello_snowflake_64_112 /hello_snowflake

# Run the binary - prints "Hello, Snowflake" and exits 0
CMD ["/hello_snowflake"]
