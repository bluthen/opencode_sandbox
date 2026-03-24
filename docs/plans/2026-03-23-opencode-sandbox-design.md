# Design: OpenCode Docker Sandbox

**Date:** 2026-03-23  
**Status:** Approved

## Goal

A script (`opencode-sandbox`) that launches OpenCode inside a Docker container with the current directory mounted as the workspace. The container provides a rich set of developer tools while isolating OpenCode from host credentials and the home directory (except for the OpenCode config).

## Approach

Shell script + Dockerfile. The script is installed to PATH by the user. The Dockerfile lives in this repo and is built once to produce the `opencode-sandbox:latest` image.

## Artifacts

| File | Purpose |
|------|---------|
| `Dockerfile` | Defines the sandbox image |
| `opencode-sandbox` | Shell script — the installed command |

## Container Software

- **OS:** Ubuntu 24.04 LTS
- **System tools:** curl, git, build-essential, ca-certificates, unzip, sudo
- **Docker:** docker-ce-cli + docker-compose-plugin (from Docker's official apt repo)
- **Python:** system Python 3 + `uv` (via official installer, user-scoped)
- **Node:** Volta (user-scoped) + `node@lts` via Volta
- **OpenCode:** `npm install -g opencode-ai` (latest stable, via Volta-managed npm)

## User Model

- A non-root user `coder` is created with a configurable UID (default 1000, overridable via `--build-arg UID=$(id -u)` at build time).
- All user-scoped tools (uv, volta, node, opencode) are installed under `/home/coder`.
- The image runs as `coder`.

## Mounts

| Host path | Container path | Mode |
|-----------|---------------|------|
| `$PWD` (current dir) | `/workspace` | read-write |
| `~/.config/opencode` | `/home/coder/.config/opencode` | read-only |
| `/var/run/docker.sock` | `/var/run/docker.sock` | read-write |

## Docker Socket Access

The host Docker socket GID is detected at run time by the script (`stat -c '%g' /var/run/docker.sock`) and passed to the container via `--group-add`. This allows the `coder` user to use docker/compose commands without being root.

## Script Behaviour

1. Detect this script's own location to find the repo (and thus the `Dockerfile`).
2. Check if `opencode-sandbox:latest` image exists locally.
3. If not, build it with `docker build --build-arg UID=$(id -u) -t opencode-sandbox:latest <repo-dir>`.
4. Detect host Docker socket GID.
5. `docker run --rm -it` with all mounts, `--group-add <gid>`, working dir `/workspace`, command `opencode`.

## Security Properties

- Host home directory is **not** mounted; only `~/.config/opencode` is exposed (read-only).
- No host credentials, SSH keys, or shell history are accessible inside the container.
- Full outbound network access is available (no network restrictions).
- Docker socket is mounted — OpenCode can run containers on the host daemon. This is a deliberate trade-off for tool access.

## Out of Scope

- Multiple OpenCode config profiles
- Offline/air-gapped operation
- Windows host support (Linux/macOS only)
