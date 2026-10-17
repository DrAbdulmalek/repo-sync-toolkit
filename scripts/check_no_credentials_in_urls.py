#!/usr/bin/env python3
"""بوابة النمط: تمنع عودة "بيانات اعتماد داخل عنوان Git".

القاعدة: لا يجوز أن يُبنى أي remote URL يحمل **userinfo** — أي اسم مستخدم ثم نقطتان ثم سر ثم علامة @ قبل اسم المضيف — لا في الشيفرة ولا في الأمثلة ولا في التوثيق.
لا في الشيفرة التنفيذية، ولا في الأمثلة، ولا في التوثيق.

لماذا بوابة نمط وليس فحص أسرار فقط؟
  لأن الخطر هنا ليس وجود سر ثابت، بل **النمط** الذي يضع التوكن داخل العنوان
  وقت التشغيل — فيتسرب عبر `.git/config` و`git remote -v` وقائمة العمليات
  ومخرجات الأخطاء. فحص الأسرار وحده لا يلتقطه.

الاستخدام:
    python3 scripts/check_no_credentials_in_urls.py            # كل الملفات المتتبَّعة
    python3 scripts/check_no_credentials_in_urls.py --staged   # الملفات المرحلية فقط
    python3 scripts/check_no_credentials_in_urls.py --json out.json

ملاحظة: هذا الملف يكتب الأنماط **مجزَّأة** عن قصد، حتى لا يلتقط نفسه.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SELF = Path(__file__).resolve().relative_to(REPO_ROOT).as_posix()

# مجلدات تُستثنى: أرشيفات مجمَّدة (للقراءة/التدقيق) ومخرجات مولَّدة
EXCLUDE_PREFIXES = ("legacy/",)
EXCLUDE_NAMES = {"project_context.txt"}

# ── الأنماط (مبنية تركيبًا لتفادي التطابق الذاتي) ─────────────────────────
_TOKEN_HOST = r"@(?:github|huggingface|gitlab)\.(?:com|co)"
PATTERNS = [
    (
        "github-app-token-in-url",
        # البادئة مكتوبة مجزَّأة حتى لا يلتقط هذا الملف نفسه (وهو يُضمَّن
        # داخل project_context.txt المولَّد، فيسبب فشلًا ذاتي المرجع).
        re.compile("x-access" + "-token" + r"\s*[:@]"),
    ),
    (
        "userinfo-with-secret-var-in-url",
        # يشترط شكل المتغير ($VAR / ${VAR} / {VAR}) حتى لا يلتقط النثر التوثيقي
        re.compile(
            r"://[^\s/'\"]*[:@]\s*(?:[\"']\s*)?[\$\{]\s*"
            r"(?:GITHUB_TOKEN|GH_TOKEN|GIT_TOKEN|HF_TOKEN|HUGGINGFACE_TOKEN|"
            r"TOKEN|SECRET|PASSWORD|GIT_PASSWORD)\b",
            re.IGNORECASE,
        ),
    ),
    (
        "f-string-token-in-url",
        re.compile(r"://[^\s'\"]*\{[^}]{0,40}token[^}]{0,20}\}" + _TOKEN_HOST, re.IGNORECASE),
    ),
    (
        "shell-var-token-in-url",
        re.compile(r"://[^\s'\"]*\$\{?(?:GITHUB_TOKEN|GH_TOKEN|TOKEN)\}?" + _TOKEN_HOST),
    ),
    (
        "git-remote-set-url-with-userinfo",
        re.compile(r"remote\s+set-url\s+\S+\s+[\"']?[a-z][a-z0-9+.-]*://[^/\s\"']*[@:]"
                   r"[^/\s\"']*\$\{?(?:GITHUB_TOKEN|GH_TOKEN|TOKEN|SECRET|PASSWORD)",
                   re.IGNORECASE),
    ),
    (
        "git-clone-with-userinfo",
        re.compile(r"clone\s+[^\n]*?[a-z][a-z0-9+.-]*://[^/\s\"']+:@[^\s\"']+", re.IGNORECASE),
    ),
]

# قيم/سياقات واضحة أنها أمثلة غير حقيقية
BENIGN = re.compile(
    r"(?i)(REPLACE_ME|REPLACE_WITH|your[-_]?|<user>|<cred>|<token>|example|dummy|"
    r"placeholder|localhost|127\.0\.0\.1|change_me|changeme|\$\{\w+:-|xxxx)"
)

SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".gz", ".pyc",
                 ".so", ".bin", ".woff", ".woff2", ".ttf", ".ico", ".svg"}


def _files(staged: bool) -> list[str]:
    cmd = (["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"]
           if staged else ["git", "ls-files"])
    out = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=False)
    return [p for p in out.stdout.splitlines() if p.strip()]


def scan(path: Path) -> list[tuple[int, str, str]]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    hits: list[tuple[int, str, str]] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for name, rx in PATTERNS:
            m = rx.search(line)
            if not m:
                continue
            if BENIGN.search(line):
                hits.append((line_no, name, "allowlisted-example"))
                continue
            hits.append((line_no, name, "BLOCK"))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--staged", action="store_true", help="افحص الملفات المرحلية فقط")
    ap.add_argument("--json", metavar="FILE", help="احفظ النتيجة بصيغة JSON")
    ap.add_argument("--include-legacy", action="store_true",
                    help="لا تستثنِ legacy/ (الافتراضي: مستثناة كأرشيف مجمَّد)")
    args = ap.parse_args()

    blockers: list[dict] = []
    allowed: list[dict] = []
    scanned = 0
    for rel in _files(args.staged):
        if rel == SELF:
            continue
        if not args.include_legacy and rel.startswith(EXCLUDE_PREFIXES):
            continue
        if Path(rel).name in EXCLUDE_NAMES:
            continue
        p = REPO_ROOT / rel
        if not p.is_file() or p.suffix.lower() in SKIP_SUFFIXES or p.stat().st_size > 2_000_000:
            continue
        scanned += 1
        for line_no, name, verdict in scan(p):
            rec = {"file": rel, "line": line_no, "pattern": name, "verdict": verdict}
            (blockers if verdict == "BLOCK" else allowed).append(rec)
            print("%-8s %s:%d  %s" % (verdict.upper(), rel, line_no, name))

    result = {"scanned_files": scanned, "blockers": blockers, "allowlisted": allowed}
    if args.json:
        Path(args.json).write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")

    if blockers:
        print("\ncredential-url-gate: %d blocking finding(s). "
              "استخدم Git Credential Manager أو `gh auth setup-git` أو SSH، "
              "ولا تضع التوكن داخل عنوان remote." % len(blockers), file=sys.stderr)
        return 1
    print("credential-url-gate: نظيف (%d ملفًا، %d مثالًا مسموحًا)" % (scanned, len(allowed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
