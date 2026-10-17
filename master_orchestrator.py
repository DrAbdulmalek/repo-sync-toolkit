#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Master Orchestrator — Automated infrastructure management
Dr. Abdulmalek - Omni Medical Suite

Usage:
  python3 master_orchestrator.py              # dry-run (preview only)
  python3 master_orchestrator.py --apply      # apply changes
  python3 master_orchestrator.py --phase 1    # specific phase only
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from datetime import datetime
from urllib.parse import urlsplit

# ══════════════════════════════════════════════════════════════
#  Settings
# ══════════════════════════════════════════════════════════════

BASE_DIR = Path(os.environ.get("REPOS_DIR", Path.home() / "github~"))
DRY_RUN = "--apply" not in sys.argv
LOG_FILE = BASE_DIR / f"orchestrator_{datetime.now():%Y%m%d_%H%M%S}.log"

ACTIVE_REPOS = [
    "omni-medical-suite",
    "medical-ocr-ground-truth",
    "medical-ocr-benchmarks",
    "medical-ocr-training-hub",
    "medical-ocr-trainer",
    "scanner-fixer",
    "telegram-forwarder",
    "ai-fuel-engine",
    "IntelliFile-app",
    "bilingual-extractor",
]

ARCHIVED_REPOS = [
    "medical-handwriting-ocr",
    "medical-ocr-postprocessor",
    "OmniFile_Processor",
    "medical-doc-processor",
]

GITHUB_USER = "DrAbdulmalek"

# ══════════════════════════════════════════════════════════════
#  Colors & Utilities
# ══════════════════════════════════════════════════════════════

class C:
    RED = '\033[91m'; GREEN = '\033[92m'; YELLOW = '\033[93m'
    BLUE = '\033[94m'; CYAN = '\033[96m'; RESET = '\033[0m'; BOLD = '\033[1m'

def log(msg, level="INFO"):
    prefix = {"INFO": "  ", "OK": "[OK] ", "WARN": "[!!] ",
              "ERROR": "[XX] ", "ACTION": "[>>] ", "DRY": "[DRY] ", "PHASE": "[##] "}
    colors = {"INFO": C.BLUE, "OK": C.GREEN, "WARN": C.YELLOW,
              "ERROR": C.RED, "ACTION": C.BLUE, "DRY": C.CYAN, "PHASE": C.BOLD + C.CYAN}
    tag = prefix.get(level, "")
    print(f"{colors.get(level, C.RESET)}{tag}{msg}{C.RESET}")
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(f"[{level}] {msg}\n")

# ── Credential hygiene ─────────────────────────────────────────────────────
# No credential may ever be placed inside a Git remote URL: it leaks through
# `.git/config`, `git remote -v`, process listings and error output.

_CRED_IN_URL = re.compile(r"^[a-z][a-z0-9+.-]*://[^/@:]+:[^/@]*@", re.IGNORECASE)
_SAFE_ERR = re.compile(r"(?:[a-z][a-z0-9+.-]*|scp-like)://[^/\s@]+:[^/\s@]*@", re.IGNORECASE)
_ENV_KEYS = re.compile(r"(?i)\b(GITHUB_TOKEN|GH_TOKEN|HF_TOKEN|HUGGINGFACE_TOKEN|"
                       r"TELEGRAM_BOT_TOKEN|GIT_PASSWORD|GIT_TOKEN)\b\s*[=:]\s*\S+")


def redact(text):
    """Strips credentials from any string before it is logged or printed."""
    if not text:
        return ""
    out = _SAFE_ERR.sub("<scheme>://<REDACTED-USERINFO>@", str(text))
    out = _ENV_KEYS.sub(lambda m: m.group(1) + "=<REDACTED>", out)
    return out


def _display(cmd):
    return " ".join(shlex.quote(str(c)) for c in cmd) if isinstance(cmd, (list, tuple)) else str(cmd)


def run(cmd, cwd=None):
    """Runs a command WITHOUT a shell (argv list) and redacts credentials in errors.

    A list is required: shell=True re-introduces both command injection (repo or
    branch names reach the shell) and credential leakage through the command line.
    """
    if DRY_RUN:
        log(f"$ {redact(_display(cmd))}", "DRY")
        return 0, "", ""
    if isinstance(cmd, str):
        raise TypeError(
            "run() requires an argv list; shell strings are rejected "
            "(command injection + credential leakage)."
        )
    try:
        r = subprocess.run(list(cmd), shell=False, cwd=cwd,
                          capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout, redact(r.stderr)
    except Exception as e:
        log(f"Failed: {redact(e)}", "ERROR")
        return 1, "", redact(str(e))


def url_has_credentials(url):
    """True when a remote URL embeds user:password (i.e. a token)."""
    if not url:
        return False
    if "://" not in url:
        # scp-like syntax (git@host:owner/repo.git) carries no password field
        return False
    try:
        parts = urlsplit(url)
    except ValueError:
        return True  # unparseable → refuse to treat it as safe
    # username-only userinfo (https://token@host/…) leaks the identity too
    return bool(parts.username) or bool(parts.password) or bool(_CRED_IN_URL.match(url))


def strip_credentials(url):
    """Returns the same URL with any userinfo removed."""
    if "://" not in url:
        return url
    parts = urlsplit(url)
    if not parts.password and not parts.username:
        return url
    host = parts.hostname or ""
    if parts.port:
        host = f"{host}:{parts.port}"
    return parts._replace(netloc=host).geturl()


def assert_clean_remote(repo_path):
    """Fails closed when origin embeds credentials; scrubs it when possible."""
    rc, url, err = run(["git", "remote", "get-url", "origin"], cwd=repo_path)
    if rc != 0:
        return False, f"cannot read origin ({err.strip()[:60] or 'no such remote'})"
    url = url.strip()
    if not url_has_credentials(url):
        return True, ""
    clean = strip_credentials(url)
    rc2, _, err2 = run(["git", "remote", "set-url", "origin", clean], cwd=repo_path)
    if rc2 == 0:
        return False, "origin contained credentials; scrubbed — re-run the operation"
    return False, f"origin contains credentials and could not be scrubbed ({err2.strip()[:60]})"


def ensure_git_auth():
    """Verifies a credential mechanism exists. Never embeds a token in a URL."""
    if shutil.which("gh"):
        rc, _, err = run(["gh", "auth", "setup-git"])
        if rc == 0:
            return True
        log("GitHub CLI present but `gh auth setup-git` failed — run `gh auth login`.", "WARN")
        return False
    rc, helper, _ = run(["git", "config", "--get", "credential.helper"])
    if helper.strip():
        return True
    if os.environ.get("SSH_AUTH_SOCK") or (Path.home() / ".ssh" / "id_ed25519").exists() \
            or (Path.home() / ".ssh" / "id_rsa").exists():
        return True
    log("No Git credential mechanism found. Configure GitHub CLI (`gh auth login`), "
        "Git Credential Manager, or SSH. Tokens are never written into remote URLs.", "ERROR")
    return False

def repo_exists(name):
    p = BASE_DIR / name
    return p.exists() and (p / ".git").exists()

def token_available():
    """Boolean only. The token VALUE is never read into this program any more:
    a value in memory ends up in remote URLs, logs and error messages."""
    if os.environ.get("GITHUB_TOKEN"):
        return True
    secrets = Path.home() / ".config" / "git-sync-system" / "secrets.env"
    if secrets.exists():
        try:
            for line in secrets.read_text().splitlines():
                if line.startswith("GITHUB_TOKEN=") and line.split("=", 1)[1].strip():
                    return True
        except OSError:
            return False
    return False


def get_token():  # deprecated shim — kept so external callers do not break
    """DEPRECATED: returns no value by design. Use ensure_git_auth() instead."""
    log("get_token() is deprecated: credentials are supplied by a Git credential "
        "helper, never read into this script.", "WARN")
    return ""

# ══════════════════════════════════════════════════════════════
#  Phase 1: Download Missing Repos
# ══════════════════════════════════════════════════════════════

def phase1_download_missing():
    log("=" * 55, "PHASE")
    log("Phase 1: Download missing repositories", "PHASE")
    log("=" * 55, "PHASE")

    all_repos = ACTIVE_REPOS + ARCHIVED_REPOS
    downloaded, skipped, failed = 0, 0, 0
    auth_ok = ensure_git_auth()
    if not auth_ok:
        log("Continuing without verified credentials: private repositories will fail "
            "to clone. No token is ever placed in a remote URL.", "WARN")

    BASE_DIR.mkdir(parents=True, exist_ok=True)

    for repo in all_repos:
        path = BASE_DIR / repo
        if repo_exists(repo):
            log(f"{repo} (exists)", "INFO")
            skipped += 1
            continue

        log(f"{repo}...", "ACTION")
        url = f"https://github.com/{GITHUB_USER}/{repo}.git"
        if url_has_credentials(url):  # defence in depth: refuse to clone a dirty URL
            log(f"{repo}: refusing URL with embedded credentials", "ERROR")
            failed += 1
            continue
        rc, _, err = run(["git", "clone", "--depth", "1", url, str(path)], cwd=BASE_DIR)
        if rc == 0:
            log(f"{repo}", "OK")
            downloaded += 1
        else:
            log(f"{repo}: {err[:80]}", "ERROR")
            failed += 1

    log(f"Result: {downloaded} cloned | {skipped} exists | {failed} failed", "INFO")
    return downloaded

# ══════════════════════════════════════════════════════════════
#  Phase 2: Unified .flake8 Config
# ══════════════════════════════════════════════════════════════

FLAKE8_CONFIG = """[flake8]
max-line-length = 120
extend-ignore = E203, W503
exclude =
    .git,
    __pycache__,
    build,
    dist,
    .venv,
    venv,
    node_modules,
    .pytest_cache
per-file-ignores =
    __init__.py:F401
    tests/*:E501,W293
"""

def phase2_flake8_config():
    log("=" * 55, "PHASE")
    log("Phase 2: Unified .flake8 config", "PHASE")
    log("=" * 55, "PHASE")

    created = 0
    for repo in ACTIVE_REPOS:
        if not repo_exists(repo):
            continue
        flake8 = BASE_DIR / repo / ".flake8"
        if flake8.exists():
            log(f"{repo}/.flake8 (exists)", "INFO")
            continue
        log(f"{repo}/.flake8", "ACTION")
        if not DRY_RUN:
            flake8.write_text(FLAKE8_CONFIG, encoding='utf-8')
            created += 1
    log(f"Created {created} .flake8 files", "OK")
    return created

# ══════════════════════════════════════════════════════════════
#  Phase 3: CONTRIBUTING.md
# ══════════════════════════════════════════════════════════════

CONTRIBUTING_MD = """# Contributing

Thank you for your interest!

## Quick Start

1. **Fork** the repository
2. **Clone** your fork locally
3. Create a branch: `git checkout -b feature/my-feature`
4. Commit: `git commit -m 'feat: add feature'`
5. Push: `git push origin feature/my-feature`
6. Open a Pull Request

## Code Standards

- Follow **PEP 8** (see `.flake8` in root)
- Use **type hints** for public functions
- Add **docstrings** (Google style)
- Write **tests** for new features

## Commit Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: add a feature
fix: fix a bug
docs: update documentation
chore: maintenance
test: add tests
```

## Reporting Issues

Use Issue Templates in `.github/ISSUE_TEMPLATE/`
"""

def phase3_contributing():
    log("=" * 55, "PHASE")
    log("Phase 3: Create CONTRIBUTING.md", "PHASE")
    log("=" * 55, "PHASE")

    created = 0
    for repo in ACTIVE_REPOS:
        if not repo_exists(repo):
            continue
        contrib = BASE_DIR / repo / "CONTRIBUTING.md"
        if contrib.exists():
            log(f"{repo}/CONTRIBUTING.md (exists)", "INFO")
            continue
        log(f"{repo}/CONTRIBUTING.md", "ACTION")
        if not DRY_RUN:
            contrib.write_text(CONTRIBUTING_MD, encoding='utf-8')
            created += 1
    log(f"Created {created} CONTRIBUTING.md files", "OK")
    return created

# ══════════════════════════════════════════════════════════════
#  Phase 4: Archive Banners
# ══════════════════════════════════════════════════════════════

ARCHIVE_BANNER = """> **Archived Repository**
>
> This repository is now **archived**. All active development has been
> migrated to the core platform:
> **[Omni-Medical-Suite](https://github.com/DrAbdulmalek/omni-medical-suite)**
>

"""

def phase4_archive_banners():
    log("=" * 55, "PHASE")
    log("Phase 4: Add archive banners", "PHASE")
    log("=" * 55, "PHASE")

    added = 0
    for repo in ARCHIVED_REPOS:
        if not repo_exists(repo):
            log(f"{repo} (not cloned)", "INFO")
            continue
        readme = BASE_DIR / repo / "README.md"
        if not readme.exists():
            continue
        content = readme.read_text(encoding='utf-8', errors='ignore')
        if "omni-medical-suite" in content and "Archived" in content:
            log(f"{repo} (banner exists)", "INFO")
            continue
        log(f"{repo}/README.md", "ACTION")
        if not DRY_RUN:
            readme.write_text(ARCHIVE_BANNER + content, encoding='utf-8')
            added += 1
    log(f"Added {added} archive banners", "OK")
    return added

# ══════════════════════════════════════════════════════════════
#  Phase 5: Quality Audit (flake8 + bandit)
# ══════════════════════════════════════════════════════════════

def phase5_quality_audit():
    log("=" * 55, "PHASE")
    log("Phase 5: Quality audit (flake8 + bandit)", "PHASE")
    log("=" * 55, "PHASE")

    report_lines = [f"# Quality Audit — {datetime.now():%Y-%m-%d %H:%M}", ""]

    for repo in ACTIVE_REPOS[:5]:
        if not repo_exists(repo):
            continue
        log(f"Scanning {repo}...", "ACTION")

        # No `2>/dev/null`, no `| head`: hiding stderr turned "tool missing" into
        # "no issues found", which made the audit report unreadable-but-green.
        report_lines.append(f"## {repo}")
        if shutil.which("flake8"):
            rc, flake_out, flake_err = run(
                ["flake8", ".", "--count", "--select=E9,F63,F7,F82",
                 "--show-source", "--statistics"],
                cwd=BASE_DIR / repo
            )
            body = (flake_out or flake_err).strip()
            status = "errors found" if rc != 0 else "clean"
            report_lines.append(f"### Flake8 (Critical) — {status}\n```\n{body[:4000] or 'No critical errors'}\n```\n")
        else:
            report_lines.append("### Flake8 (Critical) — NOT INSTALLED\n```\nflake8 is not available in this environment\n```\n")

        if shutil.which("bandit"):
            rc, bandit_out, bandit_err = run(["bandit", "-r", ".", "-q", "-lll"], cwd=BASE_DIR / repo)
            body = (bandit_out or bandit_err).strip()
            status = "issues found" if rc != 0 else "clean"
            report_lines.append(f"### Bandit (High) — {status}\n```\n{body[:4000] or 'No high issues'}\n```\n")
        else:
            report_lines.append("### Bandit (High) — NOT INSTALLED\n```\nbandit is not available in this environment\n```\n")

    report_path = BASE_DIR / "quality_audit_report.md"
    if not DRY_RUN:
        report_path.write_text("\n".join(report_lines), encoding='utf-8')
        log(f"Report: {report_path}", "OK")
    return len(report_lines)

# ══════════════════════════════════════════════════════════════
#  Phase 6: Push All Changes
# ══════════════════════════════════════════════════════════════

def phase6_push_all():
    log("=" * 55, "PHASE")
    log("Phase 6: Push all changes to GitHub", "PHASE")
    log("=" * 55, "PHASE")

    if DRY_RUN:
        log("Would push changes to all repos", "DRY")
        return 0

    pushed = 0
    if not ensure_git_auth():
        log("Push aborted: no credential helper is configured. Configure GitHub CLI, "
            "Git Credential Manager, or SSH — never a token inside the remote URL.", "ERROR")
        return 0
    for repo in ACTIVE_REPOS + ARCHIVED_REPOS:
        if not repo_exists(repo):
            continue
        rc, status, _ = run(["git", "status", "--porcelain"], cwd=BASE_DIR / repo)
        if not status.strip():
            log(f"{repo} (clean)", "INFO")
            continue
        log(f"{repo}...", "ACTION")
        clean, why = assert_clean_remote(BASE_DIR / repo)
        if not clean:
            log(f"{repo}: {why}", "ERROR")
            continue
        rc, branch, _ = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=BASE_DIR / repo)
        branch = branch.strip()
        if not re.fullmatch(r"[A-Za-z0-9._/-]+", branch or ""):
            log(f"{repo}: unexpected branch name; refusing to push", "ERROR")
            continue
        rc, _, err = run(["git", "push", "origin", branch], cwd=BASE_DIR / repo)
        if rc == 0:
            log(f"{repo}", "OK")
            pushed += 1
        else:
            log(f"{repo}: {err[:80]}", "ERROR")
    log(f"Pushed {pushed} repos", "OK")
    return pushed

# ══════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════

def main():
    print(f"\n{C.BOLD}{C.CYAN}{'=' * 57}{C.RESET}")
    print(f"{C.BOLD}{C.CYAN}  Master Orchestrator — Omni Medical Suite{C.RESET}")
    print(f"{C.BOLD}{C.CYAN}{'=' * 57}{C.RESET}")

    if DRY_RUN:
        print(f"\n{C.YELLOW}{C.BOLD}  DRY-RUN — no changes will be made{C.RESET}")
        print(f"{C.YELLOW}  To apply: python3 master_orchestrator.py --apply{C.RESET}\n")
    else:
        print(f"\n{C.RED}{C.BOLD}  APPLY MODE — changes will be made{C.RESET}\n")

    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, 'w', encoding='utf-8') as f:
        f.write(f"Orchestrator — {datetime.now()}\nMode: {'APPLY' if not DRY_RUN else 'DRY-RUN'}\n\n")

    target_phase = None
    if "--phase" in sys.argv:
        idx = sys.argv.index("--phase")
        if idx + 1 < len(sys.argv):
            target_phase = int(sys.argv[idx + 1])

    phases = [
        (1, "Download missing repos", phase1_download_missing),
        (2, "Unified .flake8 config", phase2_flake8_config),
        (3, "Create CONTRIBUTING.md", phase3_contributing),
        (4, "Archive banners", phase4_archive_banners),
        (5, "Quality audit", phase5_quality_audit),
        (6, "Push all changes", phase6_push_all),
    ]

    results = {}
    for num, name, func in phases:
        if target_phase and num != target_phase:
            continue
        results[num] = func()

    print(f"\n{C.BOLD}{'=' * 57}{C.RESET}")
    print(f"{C.BOLD}  Summary:{C.RESET}")
    for num, name, _ in phases:
        if num in results:
            status = C.GREEN + str(results[num]) + C.RESET
            print(f"   {num}. {name}: {status}")
    print(f"{C.BOLD}{'=' * 57}{C.RESET}\n")

if __name__ == '__main__':
    main()