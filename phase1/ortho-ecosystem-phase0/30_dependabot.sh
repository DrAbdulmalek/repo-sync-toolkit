#!/usr/bin/env bash
# 30_dependabot.sh — الفئة ج: ترقيات التبعيات دفعيًا (الآمن فقط)
# القاعدة: minor/patch + CI أخضر → دمج. الخمسة الكبيرة تُستثنى وتُقيَّم يدويًا.
set -euo pipefail
source ./lib.sh
require_gh

# استثناءات كبيرة الخطورة — لا تُدمج آليًا (من نص البرومبت)
export EXCLUDE="marathon_ted_pipeline:32 omni-medical-suite:158 omni-medical-suite:84 medical-ocr-demo:4 medical-ocr-trainer-hf:9"

python3 - <<'EOF'
import json, subprocess, os
OWNER="DrAbdulmalek"
excl = set(os.environ.get("EXCLUDE","").split())
inv = json.load(open("inventory/live_inventory.json"))
safe, big = [], []
for r in inv:
    for p in r["open_prs"]:
        t = p["title"].lower()
        is_dep = ("dependabot" in t or t.startswith("bump ") or "chore(deps)" in t
                  or "ci: bump" in t or "update " in t and "requirement" in t)
        if not is_dep: continue
        key = f"{r['name']}:{p['n']}"
        if key in excl: big.append((r["name"], p["n"], p["title"])); continue
        # أمثلة آمنة: ترقيات actions وأدوات CI وminor
        if "ci: bump" in t or "actions/" in t or "chore(deps)" in t or "bump " in t:
            safe.append((r["name"], p["n"], p["head"], p["title"]))
print("SAFE (دفعي):", len(safe))
for s in safe: print("  ", s)
print("BIG (يدوي):", len(big))
for b in big: print("  ", b)
json.dump(safe, open("inventory/dep_safe.json","w"))
EOF

# دمج الدفعي الآمن واحدًا واحدًا مع البوابة والنسخ الاحتياطي
# إصلاح 2026-11-23: الحلقة الأصلية كانت تقسم مخرجات $(...) على كلمات لا أسطر
# (كل $entry كلمة واحدة → $2 unbound تحت set -u). القراءة الصحيحة سطرًا: repo pr head.
while read -r repo pr head; do
  [ -z "${repo:-}" ] && continue
  merge_pr "$repo" "$pr" "$head" squash || log "توقف $repo#$pr — يُترك للفحص اليدوي"
done < <(python3 -c "import json;[print(f'{r} {n} {h}') for r,n,h,t in json.load(open('inventory/dep_safe.json'))]")
log "انتهت الفئة ج"
