# ops-scripts — Project Instructions

A collection of shell scripts for ops/sysadmin tasks (PostgreSQL, Ubuntu host setup, exporters, etc.). All scripts are designed to run directly via `curl | bash` from the GitHub raw URL.

Remote: https://github.com/kekedaine/ops-scripts

## Repo Layout

- Root contains the main scripts (`pg-*.sh`, `ubuntu-*.sh`, `install-*.sh`).
- `installation-guides/` — markdown guides for each scenario.
- `references/` — reference code from other projects (gitignored, **never commit**).

## Script Conventions

### Language
- All script content (code, identifiers, comments, log messages, header docs) **must be written in English**.
- This applies to every file under the repo root (`pg-*.sh`, `ubuntu-*.sh`, `install-*.sh`, etc.).
- Vietnamese is allowed only in chat / PR descriptions, never inside scripts.

### Shebang & Strict Mode
- Always `#!/bin/bash` and `set -e`.
- Header comment: short description + local usage example + `curl | bash` example.

### Logging
- Color codes:
  ```
  GREEN='\033[0;32m'  RED='\033[0;31m'  YELLOW='\033[1;33m'  NC='\033[0m'
  ```
- Minimum helpers: `log_info`, `log_error`. Add `log_warn`, `log_success` when needed.

### Naming
- Files: kebab-case, prefixed by domain (`pg-`, `ubuntu-`, `install-`).
- Functions: snake_case, verb-first (`disable_ssh_password_auth`, `create_user`).

### Function Style
- Each script should have a `main()` function and the following entry pattern:
  ```bash
  if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
      main "$@"
  fi
  ```
- Split validation (`check_*`), action (verb-first), and summary into separate functions.

### Idempotency
- Check current state before mutating (e.g., `grep -q ... || sed -i ...`, `id "${user}" &>/dev/null`).
- Back up config files before editing: `cp file file.backup.$(date +%Y%m%d_%H%M%S)`.
- Validate config after editing and restore the backup on failure (e.g., `sshd -t`).

### Input Validation
- Validate parameter names: regex `^[a-zA-Z][a-zA-Z0-9_]*$` for identifiers.
- Require root when needed: `[[ $EUID -ne 0 ]] && exit 1`.
- Check OS / version before running distro-specific commands.

### Output
- After a successful run, print:
  - Status `✅ ...`
  - Important values (DB name, user, password, IP).
  - A sample connection string ready to copy.
- Generate passwords with: `openssl rand -base64 20 | tr -d "=+/" | cut -c1-16`.
- Get the private IP with: `hostname -I | awk '{print $1}'`.

## Distribution

Scripts are consumed via the short proxy URL (Cloudflare Worker in `cloudflare/`
that proxies to the GitHub raw URL — see `cloudflare/README.md` for deployment):
```
https://ops.bhtas.co/<script>.sh
```
The path after the host maps 1:1 to the filename at the repo root, so any new
script becomes available at `https://ops.bhtas.co/<filename>` automatically
once pushed to `main` (subject to the Worker's 60-second cache).

After adding a new script, **always update `README.md`** with the matching
`curl | bash` block.

## When Adding a New Script

1. Place the file at the repo root, alongside the other scripts.
2. `chmod +x` after creation.
3. Follow the conventions above (header, logging, main pattern).
4. Update `README.md`.
5. Optional: add a guide under `installation-guides/`.

## Out of Scope

- Do not commit anything under `references/` (reference-only).
- Do not hard-code credentials/secrets — generate at runtime or read from env.
- Do not use `--no-verify` when committing/pushing.
