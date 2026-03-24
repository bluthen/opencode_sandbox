# Named Volume .venv Isolation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `--tmpfs` venv isolation with a named Docker/Podman volume keyed on the project path, fixing Podman rootless `Permission denied` and adding per-project persistence.

**Architecture:** A single change in the `opencode-sandbox` launcher script replaces the `--tmpfs` mount
option with a named volume derived from `sha256sum` of `$PWD`. No Dockerfile changes are needed. The README
gets a cleanup section documenting how to remove accumulated volumes.

**Tech Stack:** Bash, Docker/Podman named volumes, sha256sum

---

## Chunk 1: Script and README changes

### Task 1: Replace `--tmpfs` with named volume in `opencode-sandbox`

**Files:**
- Modify: `opencode-sandbox` (the `ISOLATE_VENV` block, approximately lines 83-85)

- [ ] **Step 1: Read the current script to confirm the exact lines to change**

  Run: `grep -n "tmpfs\|ISOLATE_VENV\|VENV" opencode-sandbox`

  Expected output shows the `--tmpfs` line inside the `if $ISOLATE_VENV` block.

- [ ] **Step 2: Replace the `--tmpfs` block**

  Find this block in `opencode-sandbox`:
  ```bash
  if $ISOLATE_VENV; then
    RUN_ARGS+=("--tmpfs" "/workspace/.venv:uid=$(id -u),gid=$(id -g)")
  fi
  ```

  Replace with:
  ```bash
  if $ISOLATE_VENV; then
    VENV_VOLUME="opencode-venv-$(echo "$PWD" | sha256sum | cut -c1-12)"
    RUN_ARGS+=("--volume" "$VENV_VOLUME:/workspace/.venv")
  fi
  ```

- [ ] **Step 3: Verify the change looks correct**

  Run: `grep -A3 "ISOLATE_VENV" opencode-sandbox`

  Expected: The block now uses `VENV_VOLUME` and `--volume`, with no `--tmpfs` remaining.

- [ ] **Step 4: Commit**

  ```bash
  git add opencode-sandbox
  git commit -m "fix: use named volume for .venv isolation instead of --tmpfs

  --tmpfs uid=/gid= options are silently ignored by Podman rootless (crun),
  leaving the mount root owned by container root. Named volumes are initialized
  on first write and work correctly with both Docker and Podman + --userns=keep-id.

  Bonus: .venv is now persistent per project (keyed on sha256 of \$PWD), so uv
  does not reinstall dependencies on every sandbox launch."
  ```

---

### Task 2: Update README with volume cleanup instructions

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current README to find the right section to add cleanup docs**

  Read `README.md` — look for sections about the `.venv` isolation feature or flags like `--isolate-venv`.

- [ ] **Step 2: Add a cleanup section near the `.venv` isolation documentation**

  After any existing mention of `--isolate-venv` / `--no-isolate-venv`, add a subsection explaining
  named volume persistence and how to clean up. If no such section exists, add after the `## Usage`
  heading. The section to add (use the Write/Edit tool, not copy-paste of markdown source):

  Section heading: `#### Cleaning up project venv volumes`

  Paragraph: "Each project gets a persistent named volume for its `.venv` (keyed on the project path).
  These volumes survive container restarts and accumulate over time. To clean them up (substitute
  `podman` for `docker` if using Podman):"

  Bash code block containing:

      # List all project venv volumes
      docker volume ls | grep opencode-venv-

      # Remove the venv volume for the current project
      docker volume rm "opencode-venv-$(echo "$PWD" | sha256sum | cut -c1-12)"

      # Remove all project venv volumes
      docker volume ls -q | grep opencode-venv- | xargs docker volume rm

  Closing paragraph: "To opt out of venv isolation entirely (and use the host `.venv` directly),
  pass `--no-isolate-venv`."

- [ ] **Step 3: Verify the README section was written correctly**

  Read `README.md` and confirm:
  - The new section appears in the right location
  - The bash code block is properly fenced with a single level of backticks (not nested)
  - No raw escape characters or markdown artifacts are visible

- [ ] **Step 4: Commit**

  ```bash
  git add README.md
  git commit -m "docs: document named venv volume persistence and cleanup"
  ```
