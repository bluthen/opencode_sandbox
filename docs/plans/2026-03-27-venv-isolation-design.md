# Design: Shadow .venv with Anonymous Docker Volume

**Date:** 2026-03-27
**Status:** Implemented

## Problem

When `uv sync` is run on the host before launching the sandbox, the project's `.venv/`
directory contains Python symlinks pointing to `~/.local/share/uv/python/cpython-3.13.x/...`.
That path does not exist inside the sandbox container. Because `$PWD` is mounted as
`/workspace`, the broken `.venv` is visible inside the container and Python/uv invocations fail.

## Solution

Add `--volume /workspace/.venv` (anonymous volume, no host path) to the `docker run`
arguments in the `opencode-sandbox` launcher script. Docker creates a fresh empty volume
and mounts it at `/workspace/.venv`, shadowing the host's `.venv`. On container exit the
anonymous volume is discarded (because `opencode-sandbox` passes `--rm` to `docker run`).
The host's `.venv` is never modified.

## Change

**One file, one line:** `opencode-sandbox`

Add to `RUN_ARGS` array (after the `"$PWD:/workspace"` line):

    "--volume" "/workspace/.venv"

## Behavior Table

| Scenario | Result |
|---|---|
| No host `.venv` | Empty anonymous volume; uv works normally |
| Host `.venv` exists (broken symlinks) | Shadowed; container sees empty dir; host `.venv` preserved |
| `uv sync` run inside sandbox | Fresh venv built in anonymous volume; works correctly |
| Container exits | Anonymous volume discarded; host `.venv` unchanged |

## Out of Scope

- Persisting the in-container venv across sessions
- Auto-running `uv sync` at container startup
- Shadowing other tool directories (`node_modules`, `.tox`, etc.)
