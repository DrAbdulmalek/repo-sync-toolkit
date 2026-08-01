#!/usr/bin/env python3
"""
Secret scanner for staged git files.

Scans staged file contents for common secret patterns:
  - GitHub PAT (ghp_*, github_pat_*)
  - HuggingFace token (hf_*)
  - Telegram api_hash (32-char hex paired with api_id context)
  - Generic long base64-like tokens after 'token'/'secret'/'api_key' keys
  - AWS access key (AKIA...)
  - Private key blocks (-----BEGIN ... PRIVATE KEY-----)

Exits non-zero if any secret is found. Prints file path + line number
+ pattern name — NEVER the secret value itself.

Usage:
  python3 scan_secrets.py                # scan staged files
  python3 scan_secrets.py <file>         # scan one file
  python3 scan_secrets.py --all          # scan all tracked files

Designed as a pre-commit hook:
  ln -s ../../scan_secrets.py .git/hooks/pre-commit
  chmod +x scan_secrets.py .git/hooks/pre-commit
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# ─── Patterns ──────────────────────────────────────────────────────────────
# Each pattern: (name, regex, severity). Severity 'block' → exit non-zero.
PATTERNS: list[tuple[str, str, str]] = [
    (
        "GitHub PAT (classic)",
        r"\bghp_[A-Za-z0-9]{36,40}\b",
        "block",
    ),
    (
        "GitHub PAT (fine-grained)",
        r"\bgithub_pat_[A-Za-z0-9_]{22,}[A-Za-z0-9]{12,}\b",
        "block",
    ),
    (
        "HuggingFace token",
        r"\bhf_[A-Za-z0-9]{34,40}\b",
        "block",
    ),
    (
        "AWS access key ID",
        r"\bAKIA[0-9A-Z]{16}\b",
        "block",
    ),
    (
        "PEM private key block",
        r"-----BEGIN (?:RSA |EC |OPENSSH |PGP |DSA )?PRIVATE KEY-----",
        "block",
    ),
    (
        "Telegram api_hash (32-char hex)",
        r"\bapi[_-]?hash\s*[:=]\s*['\"]?([0-9a-fA-F]{32})\b",
        "block",
    ),
    (
        "Generic token assignment",
        r"\b(token|secret|api[_-]?key|password|passwd)\s*[:=]\s*['\"]([A-Za-z0-9_\-+/=]{20,})['\"]",
        "warn",  # could be a placeholder; flag for review
    ),
]

COMPILED = [(name, re.compile(p), sev) for name, p, sev in PATTERNS]

# Files we never scan (binary / lock files / vendored)
SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".svg",
    ".pdf", ".zip", ".gz", ".tar", ".tgz", ".bz2",
    ".pyc", ".pyo", ".so", ".o", ".a", ".dll", ".dylib",
    ".lock", ".sum", ".bin",
}


def _staged_files() -> list[Path]:
    """Return paths of staged files (added/modified), via `git diff --cached`."""
    try:
        out = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=AM"],
            stderr=subprocess.DEVNULL,
        ).decode("utf-8", errors="replace")
    except subprocess.CalledProcessException:
        return []
    return [Path(p) for p in out.splitlines() if p.strip()]


def _all_tracked_files() -> list[Path]:
    try:
        out = subprocess.check_output(
            ["git", "ls-files"], stderr=subprocess.DEVNULL
        ).decode("utf-8", errors="replace")
    except subprocess.CalledProcessException:
        return []
    return [Path(p) for p in out.splitlines() if p.strip()]


def _scan_file(path: Path) -> list[tuple[int, str, str]]:
    """Return [(line_no, pattern_name, severity), ...] for findings in path."""
    if path.suffix.lower() in SKIP_SUFFIXES:
        return []
    if not path.exists() or not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []
    findings: list[tuple[int, str, str]] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for name, rx, sev in COMPILED:
            if rx.search(line):
                findings.append((line_no, name, sev))
    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file", nargs="?", help="scan a single file (default: staged files)")
    ap.add_argument("--all", action="store_true", help="scan all tracked files")
    args = ap.parse_args()

    if args.file:
        files = [Path(args.file)]
    elif args.all:
        files = _all_tracked_files()
    else:
        files = _staged_files()

    if not files:
        print("scan-secrets: no files to scan", file=sys.stderr)
        return 0

    block_count = 0
    warn_count = 0
    for f in files:
        for line_no, name, sev in _scan_file(f):
            if sev == "block":
                block_count += 1
                print(f"BLOCK  {f}:{line_no}  {name}")
            else:
                warn_count += 1
                print(f"WARN   {f}:{line_no}  {name}")

    if block_count:
        print(
            f"\nscan-secrets: {block_count} blocking finding(s), {warn_count} warning(s). "
            "Commit blocked. Remove or redact the secret and re-stage.",
            file=sys.stderr,
        )
        return 1
    if warn_count:
        print(
            f"\nscan-secrets: {warn_count} warning(s) (review the lines above). "
            "Warnings do not block the commit.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
