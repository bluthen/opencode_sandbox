# Design: Automatic Markdown Formatting in the Sandbox

**Date:** 2026-03-30
**Status:** Implemented

## Goal

Automatically format markdown files that OpenCode creates or edits inside the sandbox container.
Formatting requirements:

- Hard-wrap prose lines at 120 characters
- Pad pipe table columns for editor readability
- Leave fenced code blocks untouched

## Chosen Approach

Use **prettier** triggered via **OpenCode's formatter system**. OpenCode automatically runs
registered formatters on every file write or edit.

## Components

### 1. `.prettierrc` — formatting config

Committed to the repo root and copied into the container at `/home/coder/.prettierrc`:

```json
{
  "proseWrap": "always",
  "printWidth": 120
}
```

- `proseWrap: "always"` — hard-wraps prose paragraphs at `printWidth`
- `printWidth: 120` — the line length limit

### 2. `prettier-md` wrapper script

A thin bash wrapper installed at `/home/coder/.local/bin/prettier-md` (on `PATH`). It explicitly
passes `--config $HOME/.prettierrc` so prettier finds the config regardless of the current working
directory (important since OpenCode operates from `/workspace`):

```bash
#!/usr/bin/env bash
exec prettier --config "$HOME/.prettierrc" --write "$@"
```

### 3. Dockerfile changes

```dockerfile
RUN /home/coder/.volta/bin/npm install -g prettier
COPY --chown=coder:coder .prettierrc /home/coder/.prettierrc
COPY --chmod=755 --chown=coder:coder prettier-md /home/coder/.local/bin/prettier-md
```

### 4. `~/.config/opencode/opencode.json` — formatter registration (manual)

Add the following to the global opencode config on the host (mounted read-only into the container):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "formatter": {
    "prettier-markdown": {
      "command": ["prettier-md", "$FILE"],
      "extensions": [".md"]
    }
  }
}
```

The `$FILE` placeholder is replaced by OpenCode with the path of the file being formatted.

## Data Flow

1. OpenCode writes or edits a `.md` file in `/workspace`
2. OpenCode checks the file extension against registered formatters
3. The `prettier-markdown` formatter matches `.md`
4. OpenCode runs: `prettier-md <file>`
5. The wrapper calls: `prettier --config /home/coder/.prettierrc --write <file>`
6. Prose lines over 120 chars are hard-wrapped
7. Pipe table columns are padded with spaces
8. Fenced code blocks are left untouched
9. File is written back in place

## Why a Wrapper Script

Prettier searches for config by walking up from the file's location. Files in `/workspace` have no
`.prettierrc` in their ancestor directories, so prettier would ignore `/home/coder/.prettierrc`
without an explicit `--config` flag. The wrapper script ensures the config is always used without
hardcoding a path in `opencode.json`.

## Files Changed

| File | Change |
| ---- | ------ |
| `Dockerfile` | Install prettier globally; copy `.prettierrc` and `prettier-md` into image |
| `.prettierrc` | New file — prettier config (120-char wrap, always wrap prose) |
| `prettier-md` | New wrapper script — calls prettier with explicit `--config $HOME/.prettierrc` |
| `~/.config/opencode/opencode.json` | Manual step — register `prettier-markdown` formatter for `.md` files |
