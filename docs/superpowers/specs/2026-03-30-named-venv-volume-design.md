# Named Volume .venv Isolation Design

**Status:** Approved

## Problem

The existing `.venv` isolation uses `--tmpfs /workspace/.venv:uid=$(id -u),gid=$(id -g)` to shadow the
host's `.venv` inside the container. This works in Docker, but fails in Podman rootless: the `uid=` and
`gid=` options in `--tmpfs` are silently ignored by crun (the OCI runtime Podman uses), leaving the tmpfs
mount root owned by container UID 0. The `coder` user (uid 1000) cannot write to it, so `uv sync` fails
with `Permission denied`.

## Solution

Replace `--tmpfs` with a **named Docker/Podman volume** keyed on the project path. Named volumes are
handled correctly by both Docker and Podman rootless — they are created with proper ownership on first
write, and the existing `--userns=keep-id` flag ensures the `coder` user maps correctly in Podman.

This also adds a user-visible benefit: the `.venv` inside the container is now **persistent per project**,
so `uv` does not reinstall dependencies on every sandbox launch.

## Volume Naming

```
opencode-venv-<12-char sha256 prefix of $PWD>
```

Example: `opencode-venv-a3f9b2c11d04`

Using a hash of the full absolute path (`$PWD`) avoids collisions across projects with the same directory
name while keeping the volume name manageable and inspectable.

## Script Change

**File:** `opencode-sandbox`

Replace:
```bash
if $ISOLATE_VENV; then
  RUN_ARGS+=("--tmpfs" "/workspace/.venv:uid=$(id -u),gid=$(id -g)")
fi
```

With:
```bash
if $ISOLATE_VENV; then
  VENV_VOLUME="opencode-venv-$(echo "$PWD" | sha256sum | cut -c1-12)"
  RUN_ARGS+=("--volume" "$VENV_VOLUME:/workspace/.venv")
fi
```

No Dockerfile changes required.

## Volume Lifecycle

Named volumes persist until explicitly removed. Users can manage them with:

```bash
# List all project venv volumes
docker volume ls | grep opencode-venv-

# Remove a specific project's venv volume
docker volume rm opencode-venv-<hash>

# Remove all project venv volumes
docker volume ls -q | grep opencode-venv- | xargs docker volume rm
```

The README should document this cleanup procedure.

## Why This Works in Podman

- Podman rootless maps the host user to a container UID via user namespaces
- `--userns=keep-id` (already present in the script) preserves the host UID mapping
- Named volumes are initialized on first write; the first process writing to the volume (the `coder` user
  via `uv sync`) establishes ownership
- No `uid=`/`gid=` kernel mount options are needed — the user namespace handles it

## Trade-offs

| | tmpfs (old) | Named volume (new) |
|---|---|---|
| Works on Docker | Yes | Yes |
| Works on Podman rootless | No (uid/gid ignored) | Yes |
| Persists across runs | No | Yes (per project) |
| Disk usage | None | Minimal (~100MB per project for typical venv) |
| Cleanup required | No | Manual (or scripted) |

## Out of Scope

- A `--clean-venv` flag to remove the current project's volume could be added later
- Volume size limits are not set; named volumes use host disk space normally
