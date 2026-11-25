#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة أرشفة GitHub للمهمة الصفرية (issue #15) — مؤمّنة بالقرار المالك.

تقرأ manifest.json (وسم archive) وتؤرشف المستودعات المرشحة عبر GitHub API
(PATCH /repos/{owner}/{repo} {"archived": true}).

الأمان (وفق شرط الإشوه: «قرار المالك يوثق هنا قبل التنفيذ»):
1. الافتراضي **dry-run** — عرض فقط، لا تغيير.
2. --apply يتطلب --confirmed أيضًا.
3. --apply يتطلب أن يكون «سجل قرارات المالك» في INVENTORY.md قد وُثّق فعلًا
   (سطر قرار معتمد غير الفارغ) — وإلا يرفض التنفيذ.
4. إعادة التشغيل آمنة: المستودع المؤرشف سلفًا يُتخطى.
5. الرمز من GH_TOKEN في البيئة ولا يُطبع أبدًا.

الاستخدام:
    python3 archive_repos.py                       # dry-run
    python3 archive_repos.py --apply --confirmed   # بعد توثيق قرار المالك
    python3 archive_repos.py --only repo1,repo2    # قائمة فرعية
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "manifest.json"
INVENTORY = HERE / "INVENTORY.md"
OWNER = "DrAbdulmalek"
API = "https://api.github.com"
PLACEHOLDER_ROW = "| — | — | — | — |"


def api(url: str, token: str, method: str = "GET", payload: dict | None = None):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "task-zero-archive")
    data = json.dumps(payload).encode() if payload is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}


def owner_decision_documented() -> bool:
    text = INVENTORY.read_text(encoding="utf-8")
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("|") and "قرار المالك: معتمد" in line and line != PLACEHOLDER_ROW:
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="تنفيذ فعلي (يتطلب --confirmed)")
    ap.add_argument("--confirmed", action="store_true", help="تأكيد صريح ثانٍ للأمان")
    ap.add_argument("--only", default=None, help="قائمة فرعية مفصولة بفواصل")
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    candidates = [a["name"] for a in manifest["assets"]
                  if a["type"] == "github_repo" and a["classification"] == "archive-candidate"]
    if args.only:
        wanted = {x.strip() for x in args.only.split(",") if x.strip()}
        unknown = wanted - set(candidates)
        if unknown:
            sys.exit(f"✖ ليست ضمن مرشحي manifest: {sorted(unknown)}")
        candidates = [c for c in candidates if c in wanted]

    print(f"مرشحو الأرشفة ({len(candidates)}):")
    for c in candidates:
        print("  ·", c)
    if not args.apply:
        print("\n[dry-run] لا تغيير — للتنفيذ: --apply --confirmed بعد توثيق قرار المالك في INVENTORY.md")
        return 0

    if not args.confirmed:
        sys.exit("✖ --apply يتطلب --confirmed أيضًا (أمان مزدوج)")
    if not owner_decision_documented():
        sys.exit("✖ سجل قرارات المالك في INVENTORY.md ما زال فارغًا — "
                 "وثّق القرار أولًا (سطر يحتوي «قرار المالك: معتمد — <القائمة>») ثم أعد التشغيل")

    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        sys.exit("✖ GH_TOKEN غير مضبوط — يجب أن يمتلك Administration: Read and write على المستودعات")

    done, skipped, failed = [], [], []
    for name in candidates:
        s, repo = api(f"{API}/repos/{OWNER}/{name}", token)
        if s == 200 and repo.get("archived"):
            skipped.append(name)
            print(f"  ⏭ {name}: مؤرشف سلفًا")
            continue
        s2, resp = api(f"{API}/repos/{OWNER}/{name}", token, "PATCH", {"archived": True})
        if s2 == 200 and resp.get("archived"):
            done.append(name)
            print(f"  ✅ {name}: مؤرشف")
        else:
            failed.append((name, s2, resp.get("message", "?")))
            print(f"  ✖ {name}: HTTP {s2} {resp.get('message', '?')}")
    print(f"\nالنتيجة: أُرشف {len(done)} · تُخُطي (سلفًا) {len(skipped)} · فشل {len(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
