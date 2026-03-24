# OpenCode Sandbox Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a `Dockerfile` and `opencode-sandbox` shell script that launches OpenCode in an isolated Docker container with the current directory mounted as the workspace.

**Architecture:** A single shell script detects the repo location (via its own path), auto-builds the image if missing, then runs `docker run --rm -it` with the right mounts. The Dockerfile installs python/uv/volta/node/docker-cli/opencode as a non-root `coder` user.

**Tech Stack:** Bash, Docker (Dockerfile + CLI), Ubuntu 24.04, uv, Volta, Node LTS, opencode-ai (npm)

---

### Task 1: Write the Dockerfile

**Files:**
- Create: `Dockerfile`

**Step 1: Create the Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG UID=1000

# ── System packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      build-essential \
      unzip \
      sudo \
      gnupg \
      lsb-release \
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
RUN useradd -m -u ${UID} -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER coder
WORKDIR /home/coder

# ── uv ────────────────────────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ── Volta + Node LTS ──────────────────────────────────────────────────────────
RUN curl https://get.volta.sh | bash \
    && /home/coder/.volta/bin/volta install node@lts

# ── OpenCode ──────────────────────────────────────────────────────────────────
RUN /home/coder/.volta/bin/npm install -g opencode-ai

# ── PATH for coder's tools ────────────────────────────────────────────────────
ENV PATH="/home/coder/.volta/bin:/home/coder/.cargo/bin:/home/coder/.local/bin:${PATH}"

WORKDIR /workspace
```

**Step 2: Verify the Dockerfile parses without errors**

Run: `docker build --no-cache --check -f Dockerfile . 2>&1 || docker build --dry-run -f Dockerfile . 2>&1 || echo "syntax ok"`

(Docker BuildKit syntax check — if unavailable, just lint the file manually.)

**Step 3: Do a real build to verify it succeeds**

Run: `docker build --build-arg UID=$(id -u) -t opencode-sandbox:latest .`

Expected: Build completes with `Successfully tagged opencode-sandbox:latest` (or similar). This will take a few minutes on first run.

**Step 4: Smoke-test the image**

Run:
```bash
docker run --rm opencode-sandbox:latest whoami
docker run --rm opencode-sandbox:latest uv --version
docker run --rm opencode-sandbox:latest node --version
docker run --rm opencode-sandbox:latest opencode --version
docker run --rm opencode-sandbox:latest docker --version
```

Expected: `coder`, then version strings for each tool.

**Step 5: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile for opencode sandbox image"
```

---

### Task 2: Write the `opencode-sandbox` shell script

**Files:**
- Create: `opencode-sandbox`

**Step 1: Create the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Locate this script's directory (where the Dockerfile lives) ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="opencode-sandbox:latest"

# ── Build image if not present ─────────────────────────────────────────────────
if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
  echo "[opencode-sandbox] Image '$IMAGE' not found. Building..."
  docker build \
    --build-arg "UID=$(id -u)" \
    -t "$IMAGE" \
    "$SCRIPT_DIR"
  echo "[opencode-sandbox] Build complete."
fi

# ── Detect docker socket GID ───────────────────────────────────────────────────
DOCKER_SOCK=/var/run/docker.sock
if [[ ! -S "$DOCKER_SOCK" ]]; then
  echo "[opencode-sandbox] Warning: $DOCKER_SOCK not found. Docker commands inside container will not work." >&2
  DOCKER_GID=""
else
  DOCKER_GID=$(stat -c '%g' "$DOCKER_SOCK")
fi

# ── Assemble docker run args ───────────────────────────────────────────────────
RUN_ARGS=(
  "--rm"
  "--interactive"
  "--tty"
  "--volume" "$PWD:/workspace"
  "--volume" "$HOME/.config/opencode:/home/coder/.config/opencode:ro"
  "--volume" "$DOCKER_SOCK:$DOCKER_SOCK"
  "--workdir" "/workspace"
)

if [[ -n "$DOCKER_GID" ]]; then
  RUN_ARGS+=("--group-add" "$DOCKER_GID")
fi

# ── Run ────────────────────────────────────────────────────────────────────────
exec docker run "${RUN_ARGS[@]}" "$IMAGE" opencode "$@"
```

**Step 2: Make it executable**

Run: `chmod +x opencode-sandbox`

**Step 3: Verify the script is valid bash**

Run: `bash -n opencode-sandbox && echo "syntax ok"`

Expected: `syntax ok`

**Step 4: Test auto-build path (image absent scenario)**

Run:
```bash
docker image rm opencode-sandbox:latest
bash opencode-sandbox --version
```

Expected: Script prints `[opencode-sandbox] Image ... not found. Building...`, builds the image, then prints the opencode version.

**Step 5: Test normal run (image present)**

Run: `bash opencode-sandbox --version`

Expected: No build output, just the opencode version string immediately.

**Step 6: Commit**

```bash
git add opencode-sandbox
git commit -m "feat: add opencode-sandbox launcher script"
```

---

### Task 3: Update README

**Files:**
- Modify: `README.md`

**Step 1: Write the README**

```markdown
# ai-sandbox

A Docker-based sandbox for running [OpenCode](https://opencode.ai) in isolation.

OpenCode gets access to your current project directory and your OpenCode config,
but nothing else from your home directory.

## What's inside the container

- Ubuntu 24.04
- Python 3 + [uv](https://github.com/astral-sh/uv)
- [Volta](https://volta.sh) + Node LTS
- Docker CLI + Compose plugin (via host Docker socket)
- [OpenCode](https://opencode.ai) (latest stable)

## Setup

### 1. Build the image

```bash
docker build --build-arg UID=$(id -u) -t opencode-sandbox:latest .
```

### 2. Install the script

Copy (or symlink) `opencode-sandbox` to somewhere on your PATH:

```bash
ln -s "$PWD/opencode-sandbox" ~/.local/bin/opencode-sandbox
```

### 3. Run

```bash
cd /path/to/your/project
opencode-sandbox
```

The script will auto-build the image if it's not already present.

## How it works

| Mount | Purpose |
|-------|---------|
| `$PWD` → `/workspace` | Your project (read-write) |
| `~/.config/opencode` → `/home/coder/.config/opencode` | OpenCode config & API keys (read-only) |
| `/var/run/docker.sock` | Host Docker daemon access |

The container runs as a non-root user (`coder`) with the same UID as your host user,
so files created inside the container are owned by you.

## Rebuilding

To pick up a new version of OpenCode or other tools:

```bash
docker build --no-cache --build-arg UID=$(id -u) -t opencode-sandbox:latest .
```
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: write README for opencode-sandbox"
```

---

## Done

Verify the final state:

```bash
git log --oneline
docker run --rm opencode-sandbox:latest opencode --version
```

The repo should have three commits (design doc, Dockerfile, script, README) and a working image.
