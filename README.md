# ai-sandbox

A Docker-based sandbox for running [OpenCode](https://opencode.ai) in isolation.

OpenCode gets access to your current project directory and your OpenCode config, but nothing else from your home
directory.

DISCLAIMER: This is a very basic sandbox. I do not make any claims to protection or security. Use at your own risk. For
much better security I recommend [clampdown](https://github.com/89luca89/clampdown).

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

| Mount                                                 | Purpose                                |
| ----------------------------------------------------- | -------------------------------------- |
| `$PWD` → `/workspace`                                 | Your project (read-write)              |
| `~/.config/opencode` → `/home/coder/.config/opencode` | OpenCode config & API keys (read-only) |
| `/var/run/docker.sock`                                | Host Docker daemon access              |

The container runs as a non-root user (`coder`) with the same UID as your host user, so files created inside the
container are owned by you.

### Injecting environment variables

Create `~/.config/opencode-sandbox/.env` to pass additional environment variables into the container at startup. This is
useful for secrets or settings (API keys, proxy settings, etc.) that you don't want checked into any project.

```dotenv
# Lines starting with # are ignored
# Blank lines are ignored

ANTHROPIC_API_KEY=sk-ant-...
HTTP_PROXY=http://proxy.corp.example.com:8080

# export prefix is accepted but not required
export SOME_TOKEN=abc123

# Quoted values — surrounding single or double quotes are stripped
MY_SECRET="hunter2"
OTHER_SECRET='correct horse battery staple'
```

If the file does not exist it is silently ignored — no error is produced.

Windows-style (CRLF) line endings are handled automatically.

**Limitations to be aware of:**

- Inline comments are **not** stripped. `KEY=value # comment` passes the value `value # comment` to the container.
- Leading and trailing whitespace in unquoted values is **not** trimmed. `KEY= value ` passes `value` (with the
  surrounding spaces).
- Keys must be valid shell identifiers (`[A-Za-z_][A-Za-z0-9_]*`). Lines with invalid keys (e.g. `1KEY=val` or
  `MY-KEY=val`) are **silently skipped**.

### Cleaning up project venv volumes

Each project gets a persistent named volume for its `.venv` (keyed on the project path). These volumes survive container
restarts and accumulate over time. To clean them up (substitute `podman` for `docker` if using Podman):

```bash
# List all project venv volumes
docker volume ls | grep opencode-venv-

# Remove the venv volume for the current project
docker volume rm "opencode-venv-$(echo "$PWD" | sha256sum | cut -c1-12)"

# Remove all project venv volumes
docker volume ls -q | grep opencode-venv- | xargs -r docker volume rm
```

## Flags

### `--config-suffix=<suffix>`

Mount an alternate set of config directories instead of the defaults. This lets you maintain multiple independent
OpenCode profiles (e.g. separate API keys or settings for personal vs. work use):

```bash
opencode-sandbox --config-suffix=personal
```

With a suffix of `personal`, the following directories are mounted instead of the defaults:

| Mount                                                                    | Purpose                                |
| ------------------------------------------------------------------------ | -------------------------------------- |
| `~/.config/opencode-personal` → `/home/coder/.config/opencode`           | OpenCode config & API keys (read-only) |
| `~/.local/share/opencode-personal` → `/home/coder/.local/share/opencode` | OpenCode data directory (read-write)   |

The `.env` file is also read from `~/.config/opencode-sandbox-personal/.env` instead of
`~/.config/opencode-sandbox/.env`.

Omit the flag to use the default directories (`~/.config/opencode`, `~/.local/share/opencode`, and
`~/.config/opencode-sandbox/.env`).

The suffix must contain only letters, digits, dashes, and underscores (`[a-zA-Z0-9_-]`).

### `--update`

To pick up a new version of OpenCode or other tools:

```bash
opencode-sandbox --update
```

This rebuilds the image from scratch (`--no-cache`) so the latest OpenCode binary and other tools are pulled fresh.

### `--clean-venv`

To wipe the current project's `.venv` volume and start fresh (exits without launching opencode):

```bash
opencode-sandbox --clean-venv
```

For manual volume management and bulk cleanup, see
[Cleaning up project venv volumes](#cleaning-up-project-venv-volumes).

### `--no-isolate-venv` / `--isolate-venv`

To opt out of venv isolation entirely (and use the host `.venv` directly), pass `--no-isolate-venv`. The default
behavior (a persistent named volume for `.venv`) can be restored with `--isolate-venv`.
