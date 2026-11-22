#!/usr/bin/env python3
"""License audit for the DrAbdulmalek account ecosystem (roadmap item P5).

Automated LICENSE audit acting as a hard barrier before any third-party
integration. All first-party projects are MIT; GPL/AGPL and non-commercial
code must never be imported as a library inside them. The approved pattern
is to consume such code as a separate CLI/service exchanging files only.

Designed to run unattended (nightly, e.g. via master_orchestrator.py):
standard library only, token via environment, machine-readable --json
output, loud exit codes. Zero third-party Python dependencies.

Usage:
    python license_audit.py --owner DrAbdulmalek
    python license_audit.py --owner DrAbdulmalek --repos omni-medical-suite,ai-fuel-engine
    python license_audit.py --owner DrAbdulmalek --repos PaddlePaddle/PaddleOCR --json
    python license_audit.py --owner DrAbdulmalek --json > license_report.json
    python license_audit.py --config /path/to/LICENSES.json --owner DrAbdulmalek
    python license_audit.py --selftest          # offline self-test (no network)

Exit codes:
    0  clean (warnings allowed)
    1  policy violations found (hard barrier tripped)
    2  config or GitHub API error (audit could not complete)

Token handling:
    Reads GH_TOKEN or GITHUB_TOKEN from the environment. The token is only
    sent as an HTTP Authorization header — never printed, never logged,
    never written to disk, never embedded in a URL.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import logging
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "LICENSES.json"

GITHUB_API = "https://api.github.com"
PER_PAGE = 100
MAX_PAGES = 20          # safety cap: up to 2000 repos per owner
REQUEST_TIMEOUT = 30    # seconds per HTTP request

LICENSE_MISSING = "NONE"             # no license file / license field null / HTTP 404
LICENSE_NOASSERTION = "NOASSERTION"  # license file present but not auto-identifiable
LICENSE_OTHER = "OTHER"              # legacy GitHub marker for custom licenses

# License classification buckets (returned by license_class)
CLASS_MISSING = "missing"
CLASS_NOT_IDENTIFIABLE = "not_identifiable"
CLASS_FORBIDDEN_DEP = "forbidden_as_dependency"
CLASS_FORBIDDEN_USE = "forbidden_use"
CLASS_REVIEW = "review_required"
CLASS_ALLOWED = "allowed"
CLASS_UNCLASSIFIED = "unclassified"

FORBIDDEN_CLASSES = {CLASS_FORBIDDEN_DEP, CLASS_FORBIDDEN_USE}

# Watchlist consumption modes
MODE_LIBRARY = "library"
APPROVED_NON_LIBRARY_MODES = {"service", "cli", "non-commercial-experiments"}

SEVERITY_VIOLATION = "violation"
SEVERITY_WARNING = "warning"
SEVERITY_INFO = "info"

logger = logging.getLogger("license_audit")

# ---------------------------------------------------------------------------
# Redaction helper (same spirit as master_orchestrator.redact)
# ---------------------------------------------------------------------------

_TOKEN_RE = re.compile(r"(gh[posru]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")


def redact(text: Any) -> str:
    """Never let a credential-shaped string reach the console or a log."""
    return _TOKEN_RE.sub("[REDACTED]", str(text))


# ---------------------------------------------------------------------------
# Policy model (LICENSES.json)
# ---------------------------------------------------------------------------


class WatchlistEntry:
    """One third-party candidate in the LICENSES.json watchlist."""

    def __init__(self, data: dict[str, Any]) -> None:
        self.name: str = str(data.get("name", "")).strip()
        slug = data.get("repo_slug")
        self.repo_slug: Optional[str] = str(slug).strip() if slug else None
        if self.repo_slug == "":
            self.repo_slug = None
        self.license: str = str(data.get("license", "unknown")).strip() or "unknown"
        self.consumption: str = str(data.get("consumption", "unassigned")).strip().casefold()
        self.verify_before_integration: bool = bool(data.get("verify_before_integration", False))
        self.note: str = str(data.get("note", "")).strip()

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "repo_slug": self.repo_slug,
            "license": self.license,
            "consumption": self.consumption,
            "verify_before_integration": self.verify_before_integration,
            "note": self.note,
        }


class LicensePolicy:
    """Parsed representation of LICENSES.json."""

    def __init__(self, data: dict[str, Any], source: str) -> None:
        self.source = source

        default = data.get("default_license")
        if not default:
            raise ValueError("policy is missing required key 'default_license'")
        self.default_license: str = str(default).strip()

        for key in ("allowed", "review_required", "forbidden_as_dependency", "forbidden_use"):
            values = data.get(key, [])
            if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
                raise ValueError(f"policy key '{key}' must be a list of strings")
            setattr(self, key, list(values))

        if not self.forbidden_as_dependency:
            raise ValueError("policy key 'forbidden_as_dependency' must not be empty (the barrier would be vacuous)")
        if not self.allowed:
            raise ValueError("policy key 'allowed' must not be empty")

        watchlist = data.get("third_party_watchlist", [])
        if not isinstance(watchlist, list):
            raise ValueError("policy key 'third_party_watchlist' must be a list")
        self.watchlist: list[WatchlistEntry] = []
        for item in watchlist:
            entry = WatchlistEntry(item)
            if not entry.name:
                raise ValueError("third_party_watchlist entries must have a 'name'")
            self.watchlist.append(entry)

        self.watchlist_by_name: dict[str, WatchlistEntry] = {
            e.name.casefold(): e for e in self.watchlist
        }


def load_policy(path: Path) -> LicensePolicy:
    """Load and parse LICENSES.json.

    Raises:
        FileNotFoundError: If the policy file does not exist.
        ValueError: If the file is not valid JSON or fails validation.
    """
    if not path.exists():
        raise FileNotFoundError(f"License policy file not found: {path}")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"License policy must be a JSON object, got {type(data).__name__}")
    return LicensePolicy(data, source=str(path))


# ---------------------------------------------------------------------------
# License classification
# ---------------------------------------------------------------------------


def normalize_spdx(spdx: str) -> str:
    """Normalise an SPDX id for comparison.

    Strips SPDX '-only' / '-or-later' suffixes (e.g. 'GPL-3.0-only' →
    'GPL-3.0') so GitHub ids match the policy's shorter forms.
    """
    s = (spdx or "").strip()
    folded = s.casefold()
    for suffix in ("-only", "-or-later"):
        if folded.endswith(suffix):
            s = s[: -len(suffix)]
            break
    return s


def _matches(spdx: str, patterns: list[str]) -> bool:
    """Glob-match an SPDX id against policy entries (case-insensitive)."""
    normalized = normalize_spdx(spdx).casefold()
    return any(
        fnmatch.fnmatch(normalized, normalize_spdx(p).casefold()) for p in patterns
    )


def license_class(spdx: str, policy: LicensePolicy) -> str:
    """Classify an SPDX id against the policy.

    Order matters: forbidden lists are checked before allowed lists so a
    misconfigured overlap always fails closed.
    """
    s = (spdx or "").strip()
    if not s or s == LICENSE_MISSING:
        return CLASS_MISSING
    if s in (LICENSE_NOASSERTION, LICENSE_OTHER):
        return CLASS_NOT_IDENTIFIABLE
    folded = normalize_spdx(s).casefold()
    # Heuristic for custom non-commercial ids (e.g. LicenseRef-NONCOMMERCIAL-*).
    if "noncommercial" in folded or "non-commercial" in folded:
        return CLASS_FORBIDDEN_USE
    if _matches(s, policy.forbidden_use):
        return CLASS_FORBIDDEN_USE
    if _matches(s, policy.forbidden_as_dependency):
        return CLASS_FORBIDDEN_DEP
    if _matches(s, policy.review_required):
        return CLASS_REVIEW
    if _matches(s, policy.allowed):
        return CLASS_ALLOWED
    return CLASS_UNCLASSIFIED


# ---------------------------------------------------------------------------
# Findings and repo classification
# ---------------------------------------------------------------------------


def _finding(severity: str, rule: str, message: str) -> dict[str, str]:
    return {"severity": severity, "rule": rule, "message": message}


def _violation(rule: str, message: str) -> dict[str, str]:
    return _finding(SEVERITY_VIOLATION, rule, message)


def _warning(rule: str, message: str) -> dict[str, str]:
    return _finding(SEVERITY_WARNING, rule, message)


def _info(rule: str, message: str) -> dict[str, str]:
    return _finding(SEVERITY_INFO, rule, message)


def _spdx_description(record: dict[str, Any]) -> str:
    spdx = record.get("license_spdx") or LICENSE_MISSING
    if record.get("http_404"):
        return f"{spdx} (GitHub returned 404 — repo missing/private or no detectable license)"
    return spdx


def classify_first_party(record: dict[str, Any], policy: LicensePolicy) -> list[dict[str, str]]:
    """First-party repo: owned by the audited account, not a fork. Expected MIT."""
    spdx = record.get("license_spdx") or LICENSE_MISSING
    cls = license_class(spdx, policy)
    if cls == CLASS_MISSING:
        return [_violation(
            "missing_license_first_party",
            f"first-party repo has no detectable license (expected {policy.default_license}); "
            f"GitHub reports: {_spdx_description(record)}",
        )]
    if cls in FORBIDDEN_CLASSES:
        return [_violation(
            "forbidden_license",
            f"forbidden license {spdx} on first-party repo — must never be a dependency; "
            "consume only as a separate CLI/service exchanging files, if at all",
        )]
    if cls == CLASS_NOT_IDENTIFIABLE:
        return [_warning(
            "license_not_identifiable",
            f"license file present but not auto-identifiable (spdx_id={spdx}); "
            f"verify it is {policy.default_license}",
        )]
    if cls == CLASS_REVIEW:
        return [_warning(
            "review_required_license",
            f"license {spdx} requires manual review before any reuse",
        )]
    if cls == CLASS_ALLOWED:
        if normalize_spdx(spdx).casefold() == normalize_spdx(policy.default_license).casefold():
            return []
        return [_warning(
            "deviates_from_default",
            f"license {spdx} is allowed but deviates from the account default "
            f"{policy.default_license}",
        )]
    return [_warning(
        "unclassified_license",
        f"license {spdx} is not present in any LICENSES.json list — review and classify it",
    )]


def classify_fork(record: dict[str, Any], policy: LicensePolicy) -> list[dict[str, str]]:
    """Fork in the account: inspection tool, not an integration. Warnings only."""
    spdx = record.get("license_spdx") or LICENSE_MISSING
    cls = license_class(spdx, policy)
    if cls in FORBIDDEN_CLASSES:
        return [_warning(
            "fork_forbidden_license",
            f"fork carries forbidden license {spdx} — contamination vector: "
            "never copy fork code into first-party repos",
        )]
    if cls == CLASS_MISSING:
        return [_warning(
            "fork_missing_license",
            f"fork has no detectable license — verify upstream provenance before any reuse "
            f"({_spdx_description(record)})",
        )]
    if cls == CLASS_NOT_IDENTIFIABLE:
        return [_warning(
            "fork_license_not_identifiable",
            f"fork license not auto-identifiable (spdx_id={spdx}) — verify upstream",
        )]
    return []


def classify_third_party(record: dict[str, Any], policy: LicensePolicy) -> list[dict[str, str]]:
    """Third-party repo not on the watchlist (queried explicitly via --repos)."""
    spdx = record.get("license_spdx") or LICENSE_MISSING
    cls = license_class(spdx, policy)
    if cls in FORBIDDEN_CLASSES:
        return [_violation(
            "off_watchlist_forbidden",
            f"third-party repo carries forbidden license {spdx} and is not on the watchlist — "
            "integration blocked; add it to LICENSES.json with an approved non-library mode "
            "only if it will be consumed as a separate CLI/service",
        )]
    if cls == CLASS_MISSING:
        return [_warning(
            "third_party_missing_license",
            f"third-party repo has no detectable license ({_spdx_description(record)}) — "
            "do not integrate",
        )]
    if cls == CLASS_NOT_IDENTIFIABLE:
        return [_warning(
            "third_party_license_not_identifiable",
            f"third-party license not auto-identifiable (spdx_id={spdx}) — manual review required",
        )]
    if cls == CLASS_REVIEW:
        return [_warning(
            "review_required_license",
            f"license {spdx} requires manual review before any reuse",
        )]
    if cls == CLASS_ALLOWED:
        return [_warning(
            "off_watchlist_candidate",
            f"license {spdx} is allowed but the repo is not on the watchlist — record it in "
            "LICENSES.json with an approved consumption mode before integrating",
        )]
    return [_warning(
        "unclassified_license",
        f"license {spdx} is not present in any LICENSES.json list — review and classify it",
    )]


def classify_watchlist(
    entry: WatchlistEntry,
    record: Optional[dict[str, Any]],
    policy: LicensePolicy,
) -> list[dict[str, str]]:
    """Watchlist entry, optionally verified against a fetched upstream record.

    `record` is None when no upstream slug is configured (or the entry is
    outside the current scope): the policy record alone is evaluated.
    """
    findings: list[dict[str, str]] = []
    recorded = entry.license.casefold()
    detected = (record or {}).get("license_spdx")
    mode = entry.consumption

    if (record or {}).get("http_404"):
        findings.append(_warning(
            "watchlist_not_found",
            f"upstream {entry.repo_slug} returned 404 — renamed, removed or private; "
            "update repo_slug in LICENSES.json",
        ))

    if recorded == "unknown":
        if record is None:
            return [_warning(
                "watchlist_unknown_license",
                f"watchlist entry '{entry.name}' has license: unknown "
                "(no upstream slug configured) — verify the license before any integration",
            )]
        findings.append(_warning(
            "watchlist_unknown_license",
            f"watchlist entry '{entry.name}' has license: unknown; upstream "
            f"{entry.repo_slug} currently reports {detected} — update LICENSES.json",
        ))
        if license_class(detected, policy) in FORBIDDEN_CLASSES:
            findings.append(_warning(
                "watchlist_forbidden_no_mode",
                f"forbidden license {detected} detected on '{entry.name}' and no approved "
                "consumption mode recorded — resolve before integration",
            ))
        return findings

    # Recorded license is known.
    if detected and detected not in (LICENSE_MISSING, LICENSE_NOASSERTION, LICENSE_OTHER) \
            and normalize_spdx(detected).casefold() != normalize_spdx(entry.license).casefold():
        findings.append(_warning(
            "watchlist_license_drift",
            f"license drift on '{entry.name}': policy records {entry.license}, "
            f"upstream now reports {detected} — re-review before integrating",
        ))

    # Effective license = detected upstream value when verifiable, else recorded.
    effective = detected if detected not in (None, LICENSE_MISSING, LICENSE_NOASSERTION, LICENSE_OTHER) \
        else entry.license
    eff_cls = license_class(effective, policy)
    if eff_cls in FORBIDDEN_CLASSES:
        if mode == MODE_LIBRARY:
            findings.append(_violation(
                "watchlist_forbidden_in_library_mode",
                f"'{entry.name}' is licensed {effective} (forbidden) with consumption mode "
                "'library' — importing it would contaminate MIT first-party repos; "
                "consume as a separate CLI/service exchanging files instead",
            ))
        elif mode in APPROVED_NON_LIBRARY_MODES:
            findings.append(_info(
                "approved_non_library_mode",
                f"'{entry.name}' licensed {effective} — approved consumption mode "
                f"'{mode}' only (never import as a dependency)",
            ))
        else:
            findings.append(_warning(
                "watchlist_mode_unassigned",
                f"'{entry.name}' licensed {effective} (forbidden) and no approved consumption "
                "mode recorded — resolve before integration",
            ))
    elif eff_cls == CLASS_REVIEW:
        findings.append(_warning(
            "review_required_license",
            f"'{entry.name}' licensed {effective} — manual review required before integration",
        ))
    elif record is None:
        findings.append(_info(
            "policy_record_only",
            f"'{entry.name}' recorded as {entry.license} (no upstream slug configured — "
            "set repo_slug to enable automatic verification)",
        ))
    return findings


# ---------------------------------------------------------------------------
# Report building
# ---------------------------------------------------------------------------


def _row_status(findings: list[dict[str, str]]) -> str:
    severities = {f["severity"] for f in findings}
    if SEVERITY_VIOLATION in severities:
        return "violation"
    if SEVERITY_WARNING in severities:
        return "warning"
    return "clean"


def _base_row(record: Optional[dict[str, Any]], fallback_repo: str, category: str) -> dict[str, Any]:
    record = record or {}
    return {
        "repo": record.get("full_name") or record.get("repo") or fallback_repo,
        "category": category,
        "license": record.get("license_spdx") or LICENSE_MISSING if record else LICENSE_MISSING,
        "fork": bool(record.get("fork")),
        "archived": bool(record.get("archived")),
        "http_404": bool(record.get("http_404")),
        "source": record.get("source", "policy-record"),
        "status": "clean",
        "rules": [],
        "messages": [],
        "findings": [],
    }


def evaluate_record(record: dict[str, Any], policy: LicensePolicy, audit_owner: str) -> dict[str, Any]:
    """Classify one fetched repo record into an audit row."""
    name = record.get("name") or record.get("repo") or "unknown"
    entry = policy.watchlist_by_name.get(name.casefold())
    if entry is not None:
        category = "watchlist"
        findings = classify_watchlist(entry, record, policy)
    elif record.get("fork"):
        category = "fork"
        findings = classify_fork(record, policy)
    elif (record.get("owner") or "").casefold() == audit_owner.casefold():
        category = "first-party"
        findings = classify_first_party(record, policy)
    else:
        category = "third-party"
        findings = classify_third_party(record, policy)
    row = _base_row(record, name, category)
    return _finalize_row(row, findings)


def evaluate_watchlist_entry(
    entry: WatchlistEntry,
    record: Optional[dict[str, Any]],
    policy: LicensePolicy,
) -> dict[str, Any]:
    """Classify one watchlist entry (upstream record may be absent)."""
    row = _base_row(record, entry.repo_slug or entry.name, "watchlist")
    row["watchlist_entry"] = entry.to_dict()
    return _finalize_row(row, classify_watchlist(entry, record, policy))


def _finalize_row(row: dict[str, Any], findings: list[dict[str, str]]) -> dict[str, Any]:
    row["findings"] = findings
    row["status"] = _row_status(findings)
    row["rules"] = [f["rule"] for f in findings]
    row["messages"] = [f["message"] for f in findings]
    return row


def build_report(
    rows: list[dict[str, Any]],
    owner: str,
    policy_source: str,
) -> dict[str, Any]:
    """Assemble the machine-readable audit report from evaluated rows."""
    violations: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []
    summary = {"first-party": 0, "fork": 0, "watchlist": 0, "third-party": 0, "clean": 0}
    repo_rows: list[dict[str, Any]] = []

    for row in rows:
        category = row["category"]
        summary[category] = summary.get(category, 0) + 1
        if row["status"] == "clean":
            summary["clean"] += 1
        for finding in row["findings"]:
            item = {
                "repo": row["repo"],
                "category": category,
                "rule": finding["rule"],
                "license": row["license"],
                "message": finding["message"],
            }
            if finding["severity"] == SEVERITY_VIOLATION:
                violations.append(item)
            elif finding["severity"] == SEVERITY_WARNING:
                warnings.append(item)
        repo_rows.append({k: v for k, v in row.items() if k != "findings"})

    return {
        "checked": len(rows),
        "violations": violations,
        "warnings": warnings,
        "ok": not violations,
        "owner": owner,
        "policy_file": policy_source,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "summary": summary,
        "repos": repo_rows,
    }


def report_exit_code(report: dict[str, Any]) -> int:
    """Map a report to its process exit code: 0 clean/warnings, 1 violations."""
    return 0 if not report["violations"] else 1


# ---------------------------------------------------------------------------
# GitHub API client (stdlib urllib; token via Authorization header only)
# ---------------------------------------------------------------------------


def get_token() -> str:
    """Read the GitHub token from the environment (GH_TOKEN, then GITHUB_TOKEN).

    The value is never printed, logged, written to disk, or embedded in a URL.
    """
    for var in ("GH_TOKEN", "GITHUB_TOKEN"):
        value = os.environ.get(var, "").strip()
        if value:
            return value
    return ""


def _api_get(path: str, token: str, params: Optional[dict[str, Any]] = None):
    """GET one JSON document from the GitHub API.

    Returns:
        (data, None) on success, or (None, {"status": int, "message": str}).
        status 0 means a network-level failure (DNS, timeout, bad JSON).
    """
    url = GITHUB_API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, method="GET")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    request.add_header("User-Agent", "repo-sync-toolkit-license-audit/1.0")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            payload = response.read().decode("utf-8")
        return json.loads(payload), None
    except urllib.error.HTTPError as exc:
        return None, {"status": exc.code, "message": redact(exc.reason)}
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError, ValueError) as exc:
        return None, {"status": 0, "message": redact(exc)}


def _record_from_api(data: dict[str, Any], slug: str) -> dict[str, Any]:
    """Extract the audit-relevant fields from a /repos payload."""
    license_info = data.get("license") or {}
    spdx = license_info.get("spdx_id") or LICENSE_MISSING
    return {
        "repo": slug,
        "name": data.get("name") or slug.split("/")[-1],
        "full_name": data.get("full_name") or slug,
        "owner": (data.get("owner") or {}).get("login") or "",
        "fork": bool(data.get("fork")),
        "archived": bool(data.get("archived")),
        "license_spdx": spdx,
        "license_name": license_info.get("name") or "",
        "source": "api",
    }


def _not_found_record(slug: str) -> dict[str, Any]:
    """HTTP 404 on a per-repo fetch is treated as license NONE (spec)."""
    owner = slug.split("/")[0] if "/" in slug else ""
    return {
        "repo": slug,
        "name": slug.split("/")[-1],
        "full_name": slug,
        "owner": owner,
        "fork": False,
        "archived": False,
        "license_spdx": LICENSE_MISSING,
        "license_name": "",
        "http_404": True,
        "source": "api-404",
    }


def fetch_repo(slug: str, token: str):
    """Fetch one repo record. Returns (record, None) or (None, error)."""
    data, err = _api_get(f"/repos/{slug}", token)
    if err:
        if err["status"] == 404:
            return _not_found_record(slug), None
        return None, err
    return _record_from_api(data, slug), None


def list_owner_repos(owner: str, token: str):
    """List all repos owned by `owner` (user endpoint with org fallback).

    Returns (records, None) or (None, error).
    """
    endpoints = (f"/users/{owner}/repos", f"/orgs/{owner}/repos")
    last_err: Optional[dict[str, Any]] = None
    for endpoint in endpoints:
        records: list[dict[str, Any]] = []
        owner_missing = False
        for page in range(1, MAX_PAGES + 1):
            data, err = _api_get(endpoint, token, {"type": "owner", "per_page": PER_PAGE, "page": page})
            if err:
                if err["status"] == 404:
                    owner_missing = True
                    break
                return None, err
            if not isinstance(data, list):
                return None, {"status": 0, "message": f"unexpected API response from {endpoint}"}
            for item in data:
                slug = item.get("full_name") or f"{owner}/{item.get('name', '')}"
                records.append(_record_from_api(item, slug))
            if len(data) < PER_PAGE:
                records.sort(key=lambda r: r["full_name"].casefold())
                return records, None
        if not owner_missing:
            return records, None  # MAX_PAGES reached
        last_err = {"status": 404, "message": f"owner '{owner}' not found ({endpoint})"}
    return None, last_err


# ---------------------------------------------------------------------------
# Audit collection
# ---------------------------------------------------------------------------


def collect_rows(
    owner: str,
    repos_filter: list[str],
    policy: LicensePolicy,
    token: str,
):
    """Gather and classify everything in scope.

    With --repos: fetch exactly those repos (bare names resolve under
    `owner`; full `owner/repo` slugs are fetched as-is — use this to check
    third-party candidates or watchlist upstreams on demand).

    Without --repos: enumerate the owner's own repos, then verify every
    watchlist upstream that has a repo_slug (license drift detection).

    Returns (rows, None) or (None, error).
    """
    rows: list[dict[str, Any]] = []

    if repos_filter:
        for item in repos_filter:
            slug = item if "/" in item else f"{owner}/{item}"
            record, err = fetch_repo(slug, token)
            if err:
                return None, err
            rows.append(evaluate_record(record, policy, owner))
        return rows, None

    records, err = list_owner_repos(owner, token)
    if err:
        return None, err
    if not records:
        logger.warning("No repositories found for owner '%s'.", owner)
    for record in records:
        rows.append(evaluate_record(record, policy, owner))

    # Watchlist sweep: verify each upstream slug that is configured.
    for entry in policy.watchlist:
        if not entry.repo_slug:
            rows.append(evaluate_watchlist_entry(entry, None, policy))
            continue
        record, err = fetch_repo(entry.repo_slug, token)
        if err:
            return None, err
        rows.append(evaluate_watchlist_entry(entry, record, policy))
    return rows, None


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def print_human(report: dict[str, Any], policy: LicensePolicy) -> None:
    """Human-readable report (mirrors governance_checker.print_status style)."""
    bar = "=" * 60
    summary = report["summary"]
    print(bar)
    print(f"  License Audit — owner: {report['owner']}")
    print(f"  Policy: {report['policy_file']} (default license: {policy.default_license})")
    print(bar)
    print(
        f"  Checked {report['checked']} repo(s): "
        f"{summary.get('first-party', 0)} first-party, {summary.get('fork', 0)} fork(s), "
        f"{summary.get('watchlist', 0)} watchlist, {summary.get('third-party', 0)} third-party"
    )
    print()
    if report["violations"]:
        print(f"  VIOLATIONS ({len(report['violations'])}) — integration barrier tripped:")
        for item in report["violations"]:
            print(f"    [VIOLATION] {item['repo']} — rule: {item['rule']}")
            print(f"        license: {item['license']}")
            print(f"        {item['message']}")
        print()
    if report["warnings"]:
        print(f"  WARNINGS ({len(report['warnings'])}):")
        for item in report["warnings"]:
            print(f"    [WARNING]  {item['repo']} — rule: {item['rule']}")
            print(f"        {item['message']}")
        print()
    if not report["violations"] and not report["warnings"]:
        print("  No findings. All licenses conform to policy.")
        print()
    print("  Details:")
    for row in report["repos"]:
        mark = {
            "clean": "[ok]       ",
            "warning": "[warning]  ",
            "violation": "[VIOLATION]",
        }[row["status"]]
        extra = f" ({row['category']}, fork)" if row["fork"] else f" ({row['category']})"
        print(f"    {mark} {row['repo']}{extra} — license: {row['license']}")
    print(bar)
    if report["violations"]:
        print(
            f"  RESULT: FAIL — {len(report['violations'])} violation(s), "
            f"{len(report['warnings'])} warning(s) — exit 1"
        )
    else:
        print(
            f"  RESULT: PASS — 0 violations, {len(report['warnings'])} warning(s) — exit 0"
        )
    print(bar)


# ---------------------------------------------------------------------------
# Self-test (offline, no network): in-memory fake records exercise the classifier
# ---------------------------------------------------------------------------

SELFTEST_POLICY = {
    "default_license": "MIT",
    "allowed": ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC"],
    "review_required": ["LGPL-3.0"],
    "forbidden_as_dependency": ["GPL-2.0", "GPL-3.0", "AGPL-3.0"],
    "forbidden_use": ["CC-BY-NC-*", "custom non-commercial"],
    "third_party_watchlist": [
        {"name": "paddleocr", "repo_slug": "acme/paddleocr", "license": "Apache-2.0", "consumption": "library"},
        {"name": "surya", "repo_slug": "acme/surya", "license": "GPL-3.0", "consumption": "service"},
        {"name": "drift-service", "repo_slug": "acme/drift-service", "license": "Apache-2.0", "consumption": "service"},
        {"name": "drift-library", "repo_slug": "acme/drift-library", "license": "Apache-2.0", "consumption": "library"},
        {"name": "rapidocr", "repo_slug": None, "license": "unknown", "consumption": "unassigned",
         "verify_before_integration": True},
        {"name": "jina-ocr", "repo_slug": None, "license": "CC-BY-NC-SA-4.0", "consumption": "non-commercial-experiments"},
    ],
}


def _selftest_record(name: str, spdx: str, owner: str = "test-owner", fork: bool = False) -> dict[str, Any]:
    return {
        "repo": f"{owner}/{name}",
        "name": name,
        "full_name": f"{owner}/{name}",
        "owner": owner,
        "fork": fork,
        "archived": False,
        "license_spdx": spdx,
        "source": "selftest",
    }


def _selftest_rows(policy: LicensePolicy) -> list[dict[str, Any]]:
    """Build the fake portfolio used by the self-test."""
    records = [
        _selftest_record("alpha", "MIT"),                       # first-party, default  → clean
        _selftest_record("beta", LICENSE_MISSING),              # first-party, no license → violation
        _selftest_record("gamma", "GPL-3.0"),                   # first-party, forbidden → violation
        _selftest_record("delta", "Apache-2.0"),                # first-party, allowed non-default → warning
        _selftest_record("epsilon", "LGPL-3.0"),                # first-party, review → warning
        _selftest_record("zeta", "AGPL-3.0", fork=True),        # fork, forbidden → warning
        _selftest_record("eta", "CC-BY-NC-4.0"),                # first-party, NC glob → violation
        _selftest_record("theta", LICENSE_NOASSERTION),         # first-party, not identifiable → warning
        _selftest_record("iota", "GPL-2.0", owner="external-dev"),   # off-watchlist third-party → violation
        _selftest_record("kappa", "Apache-2.0", owner="external-dev"),  # off-watchlist, allowed → warning
    ]
    watch_cases = [
        ("paddleocr", _selftest_record("paddleocr", "Apache-2.0", owner="acme")),    # match, library → clean
        ("surya", _selftest_record("surya", "GPL-3.0", owner="acme")),               # match, service → clean
        ("drift-service", _selftest_record("drift-service", "GPL-3.0", owner="acme")),  # drift + service → warning
        ("drift-library", _selftest_record("drift-library", "GPL-3.0", owner="acme")),  # drift + library → violation
        ("rapidocr", None),                                                          # unknown license → warning
        ("jina-ocr", None),                                                          # NC, approved mode → clean
    ]
    rows = [evaluate_record(record, policy, "test-owner") for record in records]
    for entry_name, record in watch_cases:
        entry = policy.watchlist_by_name[entry_name]
        rows.append(evaluate_watchlist_entry(entry, record, policy))
    return rows


def run_selftest() -> int:
    """Offline self-test: classify fake records, assert exit codes and structure."""
    policy = LicensePolicy(SELFTEST_POLICY, source="<selftest-embedded>")
    rows = _selftest_rows(policy)
    report = build_report(rows, owner="test-owner", policy_source=policy.source)

    checks: list[tuple[str, bool, str]] = []

    def expect(label: str, actual: Any, expected: Any) -> None:
        checks.append((label, actual == expected, f"expected {expected!r}, got {actual!r}"))

    expect("fake portfolio: checked count", report["checked"], 16)
    expect("fake portfolio: violation count", len(report["violations"]), 5)
    expect("fake portfolio: warning count", len(report["warnings"]), 8)
    expect("fake portfolio: ok flag is False", report["ok"], False)
    expect("exit code with violations", report_exit_code(report), 1)

    violation_rules = {v["rule"] for v in report["violations"]}
    expect("rule missing_license_first_party fires", "missing_license_first_party" in violation_rules, True)
    expect("rule forbidden_license fires (GPL first-party)", "forbidden_license" in violation_rules, True)
    expect("rule off_watchlist_forbidden fires", "off_watchlist_forbidden" in violation_rules, True)
    expect("rule watchlist_forbidden_in_library_mode fires",
           "watchlist_forbidden_in_library_mode" in violation_rules, True)

    warning_rules = {w["rule"] for w in report["warnings"]}
    expect("watchlist unknown-license is a warning, not a failure",
           "watchlist_unknown_license" in warning_rules
           and "watchlist_unknown_license" not in violation_rules, True)
    expect("fork forbidden license is a warning",
           "fork_forbidden_license" in warning_rules, True)

    expect("violation items carry repo/rule/license/message",
           all(k in v for v in report["violations"] for k in ("repo", "rule", "license", "message")), True)
    expect("report contains required keys",
           {"checked", "violations", "warnings", "ok"} <= set(report), True)

    warnings_only = build_report(
        [r for r in rows if r["status"] == "warning"], owner="test-owner", policy_source=policy.source)
    expect("warnings-only portfolio: ok flag is True (warnings never fail)", warnings_only["ok"], True)
    expect("warnings-only portfolio: exit code", report_exit_code(warnings_only), 0)

    clean_only = build_report(
        [r for r in rows if r["status"] == "clean"], owner="test-owner", policy_source=policy.source)
    expect("clean-only portfolio: exit code", report_exit_code(clean_only), 0)
    expect("clean-only portfolio: no warnings", len(clean_only["warnings"]), 0)

    expect("CC-BY-NC-4.0 classified forbidden_use (glob)",
           license_class("CC-BY-NC-4.0", policy), CLASS_FORBIDDEN_USE)
    expect("CC-BY-NC-SA-4.0 classified forbidden_use (glob)",
           license_class("CC-BY-NC-SA-4.0", policy), CLASS_FORBIDDEN_USE)
    expect("LicenseRef-NONCOMMERCIAL-1.0 classified forbidden_use (heuristic)",
           license_class("LicenseRef-NONCOMMERCIAL-1.0", policy), CLASS_FORBIDDEN_USE)
    expect("GPL-3.0-only normalized to forbidden_as_dependency",
           license_class("GPL-3.0-only", policy), CLASS_FORBIDDEN_DEP)
    expect("MIT classified allowed", license_class("MIT", policy), CLASS_ALLOWED)

    failed = [c for c in checks if not c[1]]
    for label, ok, detail in checks:
        print(f"  PASS  {label}" if ok else f"  FAIL  {label} ({detail})")
    print(f"selftest: {len(checks) - len(failed)}/{len(checks)} checks passed")
    if failed:
        print("selftest: FAILED", file=sys.stderr)
        return 2
    print("selftest: ALL CHECKS PASSED (offline, no network, exit 0)")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="license_audit",
        description="License compliance audit (roadmap P5): hard barrier against "
                    "GPL/AGPL/non-commercial dependency contamination of MIT first-party repos.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  python license_audit.py --owner DrAbdulmalek\n"
            "  python license_audit.py --owner DrAbdulmalek --repos omni-medical-suite,ai-fuel-engine\n"
            "  python license_audit.py --owner DrAbdulmalek --repos PaddlePaddle/PaddleOCR --json\n"
            "  python license_audit.py --selftest\n"
        ),
    )
    parser.add_argument(
        "--owner",
        default="DrAbdulmalek",
        help="GitHub account owning the first-party repos (default: DrAbdulmalek)",
    )
    parser.add_argument(
        "--config",
        default=str(DEFAULT_CONFIG_PATH),
        help="path to the license policy file (default: LICENSES.json next to this script)",
    )
    parser.add_argument(
        "--repos",
        default="",
        help="comma-separated repo scope: bare names (under --owner) or full owner/repo slugs; "
             "default: all owner repos + watchlist upstreams",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print a machine-readable report (only the JSON goes to stdout)",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run the offline self-test against in-memory fake records (no network)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="log progress to stderr",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    """CLI entry point. Returns 0 clean, 1 violations, 2 config/API error."""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(levelname)s %(message)s")

    if args.selftest:
        return run_selftest()

    try:
        policy = load_policy(Path(args.config))
    except (OSError, ValueError) as exc:
        print(f"ERROR: cannot load license policy: {redact(exc)}", file=sys.stderr)
        return 2

    owner = args.owner.strip()
    if not owner:
        print("ERROR: --owner must not be empty", file=sys.stderr)
        return 2

    token = get_token()
    if not token:
        logger.warning(
            "No GH_TOKEN/GITHUB_TOKEN set — GitHub API will be queried unauthenticated "
            "(60 requests/hour). Nightly runs should provide a token via the environment."
        )

    repos_filter = [item.strip() for item in args.repos.split(",") if item.strip()]

    try:
        rows, api_error = collect_rows(owner, repos_filter, policy, token)
    except Exception as exc:  # fail loudly but never leak secrets
        print(f"ERROR: unexpected failure during audit: {redact(exc)}", file=sys.stderr)
        return 2
    if api_error:
        status = api_error.get("status", 0)
        hint = ""
        if status == 401:
            hint = " (invalid or expired token in GH_TOKEN/GITHUB_TOKEN)"
        elif status == 403:
            hint = " (rate limit — set GH_TOKEN/GITHUB_TOKEN or retry later)"
        print(f"ERROR: GitHub API failure (status {status}): {api_error.get('message', '')}{hint}",
              file=sys.stderr)
        return 2

    report = build_report(rows, owner=owner, policy_source=policy.source)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print_human(report, policy)
    return report_exit_code(report)


if __name__ == "__main__":
    sys.exit(main())
