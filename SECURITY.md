# Security Policy — repo-sync-toolkit

> repo-sync-toolkit is a **security-sensitive utility**. It handles API
> tokens, can push to remote repositories, and can rewrite history
> (force-push, with governance). Read this document before extending it.

## Threat model

The toolkit runs locally on the operator's machine. The threats it
must defend against:

1. **Accidental secret leakage** — tokens (GitHub PAT, HuggingFace
   token, Telegram api_id/api_hash) ending up in committed files,
   logs, or stdout.
2. **Accidental destructive operations** — `git push --force` to
   `main`, `git push --tags` to a sensitive training-data repo,
   `git reset --hard` losing uncommitted work.
3. **Audit gap** — operations happening with no trail, so a mistake
   cannot be traced back to its cause.

## Defense layers (current)

### 1. Secret storage

- Tokens are stored in `~/.config/git-sync-system/secrets.env` with
  `chmod 600` (owner read/write only).
- The `token-manager.py` tool masks token values by default in all
  output. Full values are shown only with the explicit `--show` flag
  on `list` / `export`.
- `secrets.env` is loaded into the environment only when running a
  sync command — it is never sourced into a shell.

### 2. .gitignore

The following paths are git-ignored (see `.gitignore`):

- `.env`, `.env.*`, `config/settings.env`, `config/secrets.*`
- `*.session`, `*.session-journal` (Telethon sessions)
- `logs/*.log`, `logs/*.log.gz`, `logs/*.jsonl` (logs may contain
  repo paths and metadata — should not be committed)

### 3. Governance layer

`governance_checker.py` enforces per-repo policies:

- An **allowlist** of repos that may receive pushes.
- A **denylist** of archived/protected repos where pushes are never
  allowed (e.g. `ai-fuel-engine` in the audit log).
- **`deny_force_push_protected=true`** — force-push to `main` is
  denied by default on protected repos.
- **Sensitive-data repos** require explicit `--force-write` and
  confirmation (e.g. `medical-ocr-ground-truth`).

Every push/force-push decision is logged to `logs/audit.log` as a
JSON line with timestamp, repo, branch, result (allowed/denied), and
a reason string.

### 4. Audit log

`logs/audit.log` is JSONL with the schema:

```json
{
  "timestamp": "2026-06-29T22:21:39.835741+00:00",
  "operation": "push" | "force-push" | "pull" | "clone" | "sync",
  "repo": "<name>",
  "branch": "<name>",
  "result": "allowed" | "denied",
  "details": "<reason>"
}
```

The audit log does NOT contain token values, file contents, or
diffs — only repo names, branches, and governance decisions.

## Hardening checklist (for contributors)

Before extending the toolkit, verify:

- [ ] No new code path prints token values without an explicit
      `--show`/`--debug` flag.
- [ ] No new code path writes secrets to `logs/` or to stdout
      without masking.
- [ ] Any new file path that may contain secrets is added to
      `.gitignore`.
- [ ] Any new destructive git operation (e.g. `git reset --hard`,
      `git clean -fd`) goes through `governance_checker.py` and is
      audit-logged.
- [ ] Any new "sync all repos" loop has a dry-run mode and a
      per-repo confirmation for destructive operations.

## Pre-commit secret scan

`scan_secrets.py` is a small standalone scanner that scans staged files
for common secret patterns (GitHub PAT `ghp_*`, HuggingFace `hf_*`,
AWS `AKIA*`, Telegram `api_hash` 32-char hex, PEM private key blocks,
and generic `token=...`/`api_key=...` assignments). On a finding it
prints the file path + line number + pattern name — NEVER the secret
value itself — and exits non-zero so a pre-commit hook can block the
commit.

Install as a pre-commit hook:

```bash
cd repo-sync-toolkit
chmod +x scan_secrets.py
ln -s ../../scan_secrets.py .git/hooks/pre-commit
```

Or run manually:

```bash
./scan_secrets.py            # scan staged files
./scan_secrets.py <file>     # scan one file
./scan_secrets.py --all      # scan all tracked files
```

## Reporting a vulnerability

If you find a way to bypass the governance layer, leak secrets via
logs, or push to a denied repo, please open a private security
advisory on GitHub rather than a public issue.

## Reference

- `ECOSYSTEM_STATE.md` — role of repo-sync-toolkit in the ecosystem.
- `GOVERNANCE.md` — high-level governance principles.
- `config/governance.yaml` — actual allowlist / denylist / policies.
