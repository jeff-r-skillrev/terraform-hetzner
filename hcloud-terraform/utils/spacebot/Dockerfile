FROM ghcr.io/spacedriveapp/spacebot:latest

# Install Docker CLI and git on top of the debian:bookworm-slim runtime base.
# ca-certificates, curl, and gh are already present in the upstream image.
RUN apt-get update && apt-get install -y --no-install-recommends gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce-cli \
       docker-buildx-plugin \
       docker-compose-plugin \
       git \
    && rm -rf /var/lib/apt/lists/*
