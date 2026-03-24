# dotenv Injection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Read `~/.config/opencode-sandbox/.env` on the host and inject each variable into the Docker container as
`--env KEY=VALUE` args; silently skip if the file is absent.

**Architecture:** A pure-bash `.env` parser is added to `opencode-sandbox` just before the `RUN_ARGS` array is
finalised. It reads the file line-by-line, skips blank lines and `#` comments, strips a leading `export ` prefix, strips
surrounding single/double quotes from the value, and appends `--env KEY=VALUE` entries to `RUN_ARGS`.

**Tech Stack:** Bash (the existing shell script — no new dependencies)

---

### Task 1: Add the `.env` parser to `opencode-sandbox`

**Files:**

- Modify: `opencode-sandbox` (lines 89–107, between "Assemble docker run args" and the venv block)

**Step 1: Read the current file to confirm exact insertion point**

Open `opencode-sandbox` and verify the comment `# ── Assemble docker run args` is at line 89 and the `RUN_ARGS=(` array
declaration follows immediately. The new block goes **after** the closing `)` of `RUN_ARGS` (around line 98) and
**before** the venv isolation block (`if $ISOLATE_VENV`).

**Step 2: Insert the parser block**

Add the following block between the `RUN_ARGS=(...)` declaration and the `if $ISOLATE_VENV` block:

```bash
# ── Inject vars from ~/.config/opencode-sandbox/.env (if present) ─────────────
SANDBOX_ENV_FILE="$HOME/.config/opencode-sandbox/.env"
if [[ -f "$SANDBOX_ENV_FILE" ]]; then
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    # skip blank lines and comments
    [[ -z "$_line" || "$_line" == \#* ]] && continue
    # strip leading 'export ' prefix
    _line="${_line#export }"
    # split into key and value on the first '='
    _key="${_line%%=*}"
    _val="${_line#*=}"
    # strip surrounding single or double quotes from value
    if [[ "$_val" == \"*\" || "$_val" == \'*\' ]]; then
      _val="${_val:1:${#_val}-2}"
    fi
    RUN_ARGS+=("--env" "${_key}=${_val}")
  done < "$SANDBOX_ENV_FILE"
fi
```

**Step 3: Verify the script still passes shellcheck (optional but recommended)**

```bash
shellcheck opencode-sandbox
```

Expected: no errors or warnings related to the new block.

**Step 4: Smoke-test — file absent**

Ensure `~/.config/opencode-sandbox/.env` does NOT exist, then run:

```bash
bash -x ./opencode-sandbox --help 2>&1 | grep -- '--env'
```

Expected: only Docker-related `--env` lines (e.g. `DOCKER_HOST`) appear — no extra entries from a missing file.

**Step 5: Smoke-test — file present**

Create a test file:

```bash
mkdir -p ~/.config/opencode-sandbox
cat > ~/.config/opencode-sandbox/.env <<'EOF'
# a comment
SOME_TOKEN=abc123
export ANOTHER_VAR="hello world"
QUOTED_SINGLE='value'

EOF
```

Then run (dry-run by printing args instead of executing):

```bash
bash -c '
  source ./opencode-sandbox   # will fail but lets us inspect RUN_ARGS
' 2>&1 || true
```

Or more practically, inspect `docker run` would-be args by temporarily replacing `exec docker run` with
`echo docker run` and running the script:

```bash
# Temporarily patch for inspection
sed 's/^exec docker run/echo DRYRUN docker run/' opencode-sandbox | bash
```

Expected output includes:

```
--env SOME_TOKEN=abc123 --env ANOTHER_VAR=hello world --env QUOTED_SINGLE=value
```

(Quotes stripped, `export` prefix stripped, blank lines and comments skipped.)

**Step 6: Restore any test files and commit**

```bash
rm -f ~/.config/opencode-sandbox/.env   # remove test file if desired
git add opencode-sandbox
git commit -m "feat: inject ~/.config/opencode-sandbox/.env vars into container"
```

---

### Task 2: Update README to document the feature

**Files:**

- Modify: `README.md`

**Step 1: Find the existing configuration/usage section**

Scan `README.md` for the section that describes environment variables or Docker volume mounts. The new documentation
belongs near that section.

**Step 2: Add documentation**

Add a subsection (after the existing environment/volume docs) along these lines:

```markdown
### Per-user environment variables

If `~/.config/opencode-sandbox/.env` exists, its variables are injected into the container at startup. This is useful
for secrets or settings you don't want to check into the project (API keys, proxy settings, etc.).

The file uses standard `.env` syntax:
```

# comments are ignored

MY_API_KEY=abc123 export ANOTHER_VAR="hello world" SINGLE_QUOTED='value'

```

Blank lines and `#` comments are skipped. A leading `export ` prefix and
surrounding single or double quotes are stripped automatically. If the file
does not exist, no extra variables are added and no error is produced.
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document ~/.config/opencode-sandbox/.env env injection"
```
