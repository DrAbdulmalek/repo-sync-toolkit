#!/usr/bin/env bash
# 30_dependabot.sh — الفئة ج: ترقيات التبعيات دفعيًا (الآمن فقط بعد تصنيف الإصدار الفعلي)
#
# جولة إصلاح 5 (2026-11-23) — إصلاح تصنيف Dependabot:
#   المشكلة: التصنيف القديم كان يقرأ العنوان فقط ("chore(deps)" أو "bump " أو "actions/")
#   فسُمّحت ترقيات Major فعلية لأن عناوينها تبدأ بـchore(deps) — حالات حية موثقة:
#   pandas >=2.0.0→>=3.1.1، opencv-python-headless >=4.8.0→>=5.1.0.95، Pillow >=10.0.0→>=13.0.0.
#   الآن: العنوان يحدد المرشحين للتصنيف فقط؛ قرار الأمان من بيانات الإصدار القديم/الجديد
#   المستخرجة من جسم الـPR (API) — لا من العنوان ولا نوع العبارة فيه:
#     MAJOR   → BIG: مراجعة يدوية، لا يدخل الدمج الآلي أبدًا.
#     MINOR   → لا يدخل الدمج الآلي إلا بتفعيل صريح للسياسة (DEP_POLICY_ALLOW_MINOR=1).
#     PATCH   → مرشح للدمج الآلي بعد بقية البوابات (premerge_gate + backup + verify).
#     إصدار غير قابل للتحليل / بيانات ناقصة / متساوية → UNKNOWN: لا يدخل SAFE أبدًا، بلا تخمين.
#     GitHub Actions → سياسة محافظة: MAJOR/MINOR مراجعة يدوية، PATCH فقط مرشحة.
#     التحديثات المجمّعة → أي Major واحدة غير مستثناة أو أي UNKNOWN تمنع تصنيفها آمنة.
#     الاستثناءات الخمسة تُفحص قبل كل تصنيف (EXEMPT): لا يستطيع أي مسار جديد تجاوزها.
#   محلل الإصدارات: رقمي صارم يستوعب الصيغ الشائعة (v-prefix، >=/==/~، 1-4 مكونات)؛
#   وما لا يطابق يعامل UNKNOWN — لا تخمين عند تعذر التحليل.

DEP_EXCLUDE_DEFAULT="marathon_ted_pipeline:32 omni-medical-suite:158 omni-medical-suite:84 medical-ocr-demo:4 medical-ocr-trainer-hf:9"

# ── المصنّف (قابل للاختبار: ملف JSONL دخول ← تصنيف ← stdout، بلا gh وبلا شبكة) ──
dep_classify() { # $1=ملف JSONL {repo,n,head,title,body} → stdout: JSONL مصنف لكل صف
  EXCLUDE="${EXCLUDE:-$DEP_EXCLUDE_DEFAULT}" \
  DEP_POLICY_ALLOW_MINOR="${DEP_POLICY_ALLOW_MINOR:-0}" \
  python3 -I - "$1" <<'PYEOF'
import json, os, re, sys

EXCLUDE = set(os.environ.get("EXCLUDE", "").split())
ALLOW_MINOR = os.environ.get("DEP_POLICY_ALLOW_MINOR", "0") == "1"

_CLEAN = re.compile(r"^\s*[><=!~^]+\s*")  # إزالة عمليات القيود من بداية المواصفة
def parse_ver(s):
    """رقمي صارم: يستوعب v-prefix و>= و1-4 مكونات؛ غير ذلك None بلا تخمين."""
    if not s:
        return None
    s = _CLEAN.sub("", s.strip())
    s = s.rstrip(".,;:)").strip()
    if len(s) > 1 and s[0] in "vV" and s[1].isdigit():
        s = s[1:]
    if not s or not s[0].isdigit():
        return None
    vals = []
    for p in s.split("."):
        if not p.isdigit():
            return None
        vals.append(int(p))
    return tuple(vals)

def bump_type(ov, nv):
    """تصنيف الترقية من زوج إصدارات محلَّلين — الافتراض الخاطئ هنا: UNKNOWN."""
    if ov is None or nv is None:
        return "UNKNOWN"
    n = max(len(ov), len(nv))
    a = ov + (0,) * (n - len(ov))
    b = nv + (0,) * (n - len(nv))
    if a == b:
        return "UNKNOWN"  # لا ترقية مثبتة (إصداران متساويان)
    if a[0] != b[0]:
        return "MAJOR"
    if a[1] != b[1]:
        return "MINOR"
    return "PATCH"

# صيغتا Dependabot الفعليتان في جسم الـPR: manifest (Bumps [pkg](url) from X to Y)
# وrequirements (Updates `pkg` requirement from X to Y) — المجمّعة تكرر الصيغة.
_BUMP = re.compile(
    r"(?:Bumps?\s+\[([^\]]+)\]\([^)]*\)|Updates?\s+`([^`]+)`(?:\s+requirement)?)"
    r"\s+from\s+(\S+)\s+to\s+(\S+)", re.IGNORECASE)

def bumps_from_body(body):
    out = []
    for m in _BUMP.finditer(body or ""):
        dep = (m.group(1) or m.group(2) or "").strip()
        out.append({"dep": dep, "old": m.group(3), "new": m.group(4),
                    "type": bump_type(parse_ver(m.group(3)), parse_ver(m.group(4)))})
    return out

def classify(row):
    key = "%s:%d" % (row.get("repo", ""), int(row.get("n", 0)))
    bumps = bumps_from_body(row.get("body"))
    if key in EXCLUDE:
        # الاستثناءات قبل أي تصنيف: لا يستطيع أي تصنيف جديد (حتى Patch) دفعها للآلي
        return "EXEMPT", False, "استثناء معتمد — مراجعة يدوية حصرًا، لا يتجاوزه أي تصنيف", bumps
    if not bumps:
        return "UNKNOWN", False, "لا بيانات إصدار قديم/جديد في جسم الـPR — لا يمكن إثبات النوع", bumps
    types = [b["type"] for b in bumps]
    is_actions = (row.get("head") or "").startswith("dependabot/github_actions/") \
        or any("actions/" in b["dep"] for b in bumps)
    if "MAJOR" in types:
        return "BIG", False, "ترقية Major غير مستثناة (من بيانات الإصدار، لا العنوان)", bumps
    if "UNKNOWN" in types:
        return "UNKNOWN", False, "مكوّن مجمّع أو إصدار لا يمكن إثبات نوعه", bumps
    if is_actions and "MINOR" in types:
        return "BIG", False, "actions: minor للمراجعة اليدوية (سياسة محافظة)", bumps
    if "MINOR" in types:
        if not ALLOW_MINOR:
            return "MINOR", False, "minor خارج السياسة الافتراضية (لم تُفعَّل صراحةً)", bumps
        return "MINOR", True, "minor مسموح بالسياسة المعتمدة صراحةً", bumps
    return "PATCH", True, "ترقية patch — مرشحة للدمج الآلي بعد بقية البوابات", bumps

for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    row = json.loads(line)
    cat, elig, why, bumps = classify(row)
    row.update({"category": cat, "eligible": elig, "reason": why, "bumps": bumps})
    print(json.dumps(row, ensure_ascii=False))
PYEOF
}

# ── استخراج قائمة الدمج الآلي: eligible حصرًا + إعادة فحص الفئة هنا (دفاع مضاعف) ──
dep_safe_extract() { # $1=ملف مصنّف → stdout: JSON array من [repo,n,head,title]
  python3 -I - "$1" <<'PYEOF'
import json, sys
safe = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    if d.get("eligible") is True and d.get("category") in ("PATCH", "MINOR"):
        safe.append([d["repo"], d["n"], d.get("head", ""), d.get("title", "")])
    elif d.get("eligible") is True:
        raise SystemExit("رفض fail-closed: صف eligible بفئة غير مسموحة: %s:%s (%s)"
                         % (d.get("repo"), d.get("n"), d.get("category")))
json.dump(safe, sys.stdout)
PYEOF
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
  require_gh

  # استثناءات كبيرة الخطورة — لا تُدمج آليًا (من نص البرومبت)؛ تُفحص قبل أي تصنيف
  export EXCLUDE="${EXCLUDE:-$DEP_EXCLUDE_DEFAULT}"
  export DEP_POLICY_ALLOW_MINOR="${DEP_POLICY_ALLOW_MINOR:-0}"   # افتراضيًا: minor لا يُدمج آليًا

  # المرشحون للتصنيف: كشف شامل (العنوان أو فرع dependabot/) — الشمول الزائد آمن لأن
  # القرار النهائي من بيانات الإصدار وليس من هذه المرحلة
  python3 - <<'EOF'
import json, subprocess
OWNER = "DrAbdulmalek"
inv = json.load(open("inventory/live_inventory.json"))
cands = []
for r in inv:
    for p in r["open_prs"]:
        t = p["title"].lower()
        head = p.get("head", "")
        is_dep = ("dependabot" in t or t.startswith("bump ") or "chore(deps)" in t
                  or "ci: bump" in t or "update " in t and "requirement" in t
                  or head.startswith("dependabot/"))
        if is_dep:
            cands.append({"repo": r["name"], "n": p["n"], "head": head, "title": p["title"]})
# مصدر التصنيف: جسم الـPR من API (بيانات الإصدار الفعلية) — فشل الجلب ⇒ body فارغ ⇒ UNKNOWN
for c in cands:
    try:
        res = subprocess.run(
            ["gh", "api", "repos/%s/pulls/%d" % (OWNER, c["n"]), "--jq", ".body"],
            capture_output=True, text=True, timeout=60)
        c["body"] = (res.stdout or "").strip() if res.returncode == 0 else ""
    except Exception:
        c["body"] = ""
with open("inventory/dep_candidates.jsonl", "w") as f:
    for c in cands:
        f.write(json.dumps(c, ensure_ascii=False) + "\n")
print("مرشحون للتصنيف:", len(cands))
EOF

  dep_classify inventory/dep_candidates.jsonl > inventory/dep_classified.jsonl
  dep_safe_extract inventory/dep_classified.jsonl > inventory/dep_safe.json

  # العدادات الموثقة — تُسجل في سجل التشغيل ولا تُقدَّر يدويًا
  COUNTS=$(python3 -I - inventory/dep_classified.jsonl <<'EOF'
import collections, json, sys
c = collections.Counter()
elig = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    c[d["category"]] += 1
    elig += 1 if d["eligible"] else 0
print("التصنيف: SAFE(آلي)=%d | PATCH=%d MINOR=%d BIG=%d UNKNOWN=%d EXEMPT=%d"
      % (elig, c["PATCH"], c["MINOR"], c["BIG"], c["UNKNOWN"], c["EXEMPT"]))
EOF
)
  log "$COUNTS"

  # قائمة المراجعة اليدوية (غير الآلي) مع الأسباب — للفحص اليدوي الموثق
  python3 -I - inventory/dep_classified.jsonl <<'EOF'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
with open("inventory/dep_review.json", "w") as f:
    json.dump([d for d in rows if not d["eligible"]], f, ensure_ascii=False, indent=1)
EOF

  # دمج الدفعي الآمن واحدًا واحدًا مع البوابة والنسخ الاحتياطي
  # إصلاح 2026-11-23: الحلقة الأصلية كانت تقسم مخرجات $(...) على كلمات لا أسطر
  # (كل $entry كلمة واحدة → $2 unbound تحت set -u). القراءة الصحيحة سطرًا: repo pr head.
  while read -r repo pr head; do
    [ -z "${repo:-}" ] && continue
    merge_pr "$repo" "$pr" "$head" squash || log "توقف $repo#$pr — يُترك للفحص اليدوي"
  done < <(python3 -c "import json;[print(f'{r} {n} {h}') for r,n,h,t in json.load(open('inventory/dep_safe.json'))]")
  log "انتهت الفئة ج"
fi
