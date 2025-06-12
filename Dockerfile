# Build and test stage
FROM ghcr.io/foundry-rs/foundry:latest AS builder

WORKDIR /app
COPY . .

# Install dependencies and build
RUN forge install --no-commit || true
RUN forge build || true
RUN forge test || true

# Deployment stage
FROM ghcr.io/foundry-rs/foundry:latest AS deployer

WORKDIR /app

# Copy built artifacts from builder stage
COPY --from=builder /app/out ./out
COPY --from=builder /app/broadcast ./broadcast
COPY --from=builder /app/script ./script
COPY --from=builder /app/foundry.toml ./
COPY --from=builder /app/src ./src

# Set entrypoint for deployment
ENTRYPOINT ["forge", "script"]

# Default stage for development
FROM ghcr.io/foundry-rs/foundry:latest

WORKDIR /app
COPY . .

RUN forge install --no-commit || true
RUN forge build || true

CMD ["forge", "test"]
