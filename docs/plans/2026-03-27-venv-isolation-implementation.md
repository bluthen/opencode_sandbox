# .venv Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Shadow the host's `.venv` directory with an anonymous Docker volume so the sandbox container always starts with a clean Python environment.

**Architecture:** Add one `--volume /workspace/.venv` argument to the `docker run` call in the `opencode-sandbox` Bash launcher. No Dockerfile changes required. Docker creates a fresh empty anonymous volume at `/workspace/.venv`, shadowing the host bind-mounted `.venv`. The anonymous volume is discarded on container exit (via `--rm`).

**Tech Stack:** Bash, Docker

---

### Task 1: Write design doc

**Files:**
- Create: `docs/plans/2026-03-27-venv-isolation-design.md`

**Step 1: Write the file**

Content: see `docs/plans/2026-03-27-venv-isolation-design.md`

**Step 2: Commit**

```bash
git add docs/plans/2026-03-27-venv-isolation-design.md
git commit -m "docs: add .venv isolation design document"
```

---

### Task 2: Add anonymous volume for `.venv` in launcher script

**Files:**
- Modify: `opencode-sandbox` (the `RUN_ARGS` array)

**Step 1: Make the change**

In `opencode-sandbox`, inside `RUN_ARGS=(...)`, after `"--volume" "$PWD:/workspace"`, add:

```bash
  "--volume" "/workspace/.venv"
```

Result:

```bash
RUN_ARGS=(
  "--rm"
  "--interactive"
  "--volume" "$PWD:/workspace"
  "--volume" "/workspace/.venv"
  "--volume" "$HOME/.config/opencode:/home/coder/.config/opencode:ro"
  "--volume" "$HOME/.local/share/opencode:/home/coder/.local/share/opencode"
  "--workdir" "/workspace"
)
```

**Step 2: Verify syntax**

```bash
bash -n opencode-sandbox
```

Expected: no output (no syntax errors)

**Step 3: Manual verification (inside sandbox)**

From a Python project that has a host-created `.venv`:

```bash
opencode-sandbox
# Inside container:
ls /workspace/.venv   # Should be empty
uv sync               # Should succeed
python -c "import sys; print(sys.executable)"  # Should show container path
```

**Step 4: Commit**

```bash
git add opencode-sandbox
git commit -m "feat: shadow .venv with anonymous volume to prevent broken host symlinks"
```

---

### Status

- [x] Task 1: Design doc — committed f1826f4
- [x] Task 2: Implementation — committed 25320d3
