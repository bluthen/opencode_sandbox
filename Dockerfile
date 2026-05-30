# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG UID=1000

# ── System packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      wget \
      rustc \
      cargo \
      openjdk-11-jdk \
      jq \
      openssh-client \
      git \
      build-essential \
      zip \
      unzip \
      sudo \
      gnupg \
      lsb-release \
      graphviz \
      python3-full \
    && rm -rf /var/lib/apt/lists/*

# ── Docker CLI + Compose plugin ────────────────────────────────────────────────
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
         | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo \
         "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
         https://download.docker.com/linux/ubuntu \
         $(lsb_release -cs) stable" \
         > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         docker-ce-cli \
         docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user ──────────────────────────────────────────────────────────────
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u ${UID} -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

USER coder
WORKDIR /home/coder

# ── Pre-create directories that Podman would otherwise auto-create as root ────
# When a bind-mount targets a path whose parent doesn't exist in the image,
# Podman (rootless) creates the missing parent owned by root, blocking writes
# by the coder user. Pre-creating them here ensures correct ownership.
RUN mkdir -p /home/coder/.local/share

# ── PATH for coder's tools ────────────────────────────────────────────────────
ENV PATH="/home/coder/.opencode/bin:/home/coder/.volta/bin:/home/coder/.cargo/bin:/home/coder/.local/bin:${PATH}"

# ── uv ────────────────────────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ── Volta + Node LTS ──────────────────────────────────────────────────────────
RUN curl -fsSL https://get.volta.sh | bash \
    && /home/coder/.volta/bin/volta install node@lts

# ── OpenCode ──────────────────────────────────────────────────────────────────
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# ── Prettier (markdown formatter) ─────────────────────────────────────────────
RUN /home/coder/.volta/bin/npm install -g prettier
COPY --chown=coder:coder .prettierrc /home/coder/.prettierrc
# Wrapper so prettier always uses ~/prettierrc regardless of working directory
COPY --chmod=755 --chown=coder:coder prettier-md /home/coder/.local/bin/prettier-md

WORKDIR /workspace
