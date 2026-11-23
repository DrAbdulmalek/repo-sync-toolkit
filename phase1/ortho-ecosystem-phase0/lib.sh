#!/usr/bin/env bash
# lib.sh — مكتبة مشتركة لحزمة تنفيذ المرحلة 1 محليًا (توكنك يبقى على جهازك)
# الاستخدام: source ./lib.sh ثم استدعِ الدوال.
#
# سجل الإصلاحات:
#   2026-11-23 جولة 1 (مراجعة المالك):
#     1) مسار MERGED الكاذب مغلق: merge_pr لا يسجل MERGED إلا بعد verify_merged
#        من الحالة الحية (state=closed + merged=true + merge_commit_sha).
#     2) النسخة الاحتياطية بوابة فعلية: API موثوق + تحقق + فشلها يمنع الدمج.
#     3) صيغة gh v2.105: --repo OWNER/REPO NUM بدل OWNER/REPO#NUM.
#     4) فحص CI لحظي واحد fail-closed (المعلق يُسجل ويُعاد، لا انتظار حي).
#     5) run() يوثق الفشل بصدق (EXEC-FAILED) ويعود برمز خروج غير صفري.
#   2026-11-23 جولة 2 (مراجعة المالك المستقلة):
#     6) premerge_gate تحلل القيم فعليًا وترفض صراحة: غير OPEN (مغلق/مدموج
#        مسبقًا)، CONFLICTING/UNKNOWN، DIRTY/BLOCKED/BEHIND/DRAFT/UNSTABLE،
#        CHANGES_REQUESTED/REVIEW_REQUIRED، وفشل تحليل الاستجابة نفسه.
#     7) النسخة الاحتياطية مستقلة قابلة للاستعادة: لقطة بيانات pr_meta_*.json +
#        git bundle كامل للرأس مع bundle verify + اختبار استعادة فعلي في مستودع
#        تجريبي — فشل أي خطوة يمنع الدمج. BACKUP_REMOTE_URL للاختبارات.
#     8) close_pr: لا CLOSED إلا بتحقق حي (state=closed من API)، ولا ادعاء نجاح في DRY_RUN.
#   2026-11-23 جولة 3 (مراجعة المالك):
#     9) لا توكن في عنوان Git ولا في وسائط العملية: askpass مؤقت يقرأ GH_TOKEN من
#        البيئة عند سؤال git ويُحذف فور انتهاء الجلب؛ GIT_TERMINAL_PROMPT=0.
set -euo pipefail

: "${GH_TOKEN:?ضع التوكن: export GH_TOKEN=ghp_...  (لا تضع التوكن في أي ملف)}"
export GH_TOKEN
OWNER="DrAbdulmalek"
DRY_RUN="${DRY_RUN:-1}"          # افتراضي: محاكاة فقط. للتطبيق: DRY_RUN=0
LOG_FILE="${LOG_FILE:-phase1_run_$(date +%Y%m%d_%H%M%S).log}"
mkdir -p logs backups/bundles

log()  { echo "[$(date '+%F %T')] $*" | tee -a "logs/$LOG_FILE"; }
run()  { # يطبق الأمر فعليًا فقط إذا لم نكن في وضع المحاكاة؛ يعيد رمز الخروج بصدق
  if [ "$DRY_RUN" = "1" ]; then log "DRY-RUN (لن يُنفذ): $*"; else
    log "EXEC: $*"
    if "$@"; then log "EXEC-OK"; else log "EXEC-FAILED (رمز $?)"; return 1; fi
  fi
}

gh_api() { gh api "$1" ${2:+"$2"}; }   # غلاف موحد للتوثيق والتصحيح

require_gh() {
  command -v gh >/dev/null || { echo "ثبّت gh CLI أولًا: https://cli.github.com"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "المصادقة فشلت — تحقق من GH_TOKEN"; exit 1; }
  log "gh جاهز — DRY_RUN=$DRY_RUN"
}

# ── بوابة ما قبل الدمج: تحليل فعلي للقيم + رفض صريح للحالات غير الآمنة (جولة 2) ──
# كانت تعرض القيم دون فحصها؛ الآن القائمة بيضاء صارمة: OPEN + MERGEABLE +
# (CLEAN|HAS_HOOKS) + مراجعة غير مانعة — وأي قيمة مجهولة أو ناقصة = رفض.
premerge_gate() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  local f="logs/premerge_${repo}_${pr}.json"
  log "بوابة الجودة: $repo#$pr"
  if ! gh pr view --repo "$OWNER/$repo" "$pr" --json state,mergeable,mergeStateStatus,reviewDecision > "$f" 2>/dev/null; then
    log "رفض: تعذر قراءة حالة $repo#$pr من GitHub"; return 1
  fi
  local verdict
  verdict=$(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
state = d.get("state") or ""
mergeable = d.get("mergeable") or "UNKNOWN"
mss = d.get("mergeStateStatus") or "UNKNOWN"
review = d.get("reviewDecision") or ""
rv = review if review else "-"
ctx = f"[state={state} mergeable={mergeable} mss={mss} review={rv}]"
def reject(reason):
    print("REJECT " + reason + " " + ctx)
    raise SystemExit
if state != "OPEN": reject("الـPR ليس مفتوحًا (" + state + ") — مغلق أو مدموج مسبقًا")
if mergeable == "CONFLICTING": reject("تعارض دمج CONFLICTING")
if mergeable != "MERGEABLE": reject("قابلية الدمج غير مؤكدة (" + mergeable + ")")
if mss not in ("CLEAN", "HAS_HOOKS"): reject("حالة الدمج غير آمنة (" + mss + ")")
if review in ("CHANGES_REQUESTED", "REVIEW_REQUIRED"): reject("حالة المراجعة تمنع الدمج (" + review + ")")
print("OK " + ctx)
' "$f" 2>/dev/null) || verdict="REJECT تعذر تحليل استجابة البوابة"
  if [ "${verdict%% *}" = "OK" ]; then
    # بعد صحة حالة الـPR: فحص CI لحظي واحد — المعلق/الفاشل/البلا-فحوص يرفض جميعًا
    if ! gh pr checks --repo "$OWNER/$repo" "$pr" >/dev/null 2>&1; then
      log "رفض: CI غير أخضر (أو معلق/بلا فحوص) على $repo#$pr"
      return 1
    fi
    log "بوابة مقبولة: ${verdict#OK }"; return 0
  fi
  log "رفض: ${verdict#REJECT }"
  return 1
}

# ── النسخة الاحتياطية بوابة: مستقلة قابلة للاستعادة (جولة 2) ──
# (1) pr_meta_*.json لقطة بيانات الـPR من API (مجموعة عقد، ليست شيفرة).
# (2) git bundle كامل لكائنات الرأس + bundle verify من مستودع فارغ (لا متطلبات
#     مسبقة) + استعادة فعلية بالاستنساخ والتحقق من وجود الـcommit.
# فشل أي مكوّن يمنع الدمج نهائيًا. الوسم المحلي استعاضة تجميلية غير مانعة.
backup_pr() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  local tag
  tag="pre-merge/pr-${pr}-$(date +%Y%m%d)"
  local mf="backups/pr_meta_${repo}_${pr}.json"
  local bf="backups/bundles/pr_${repo}_${pr}.bundle"
  local remote="${BACKUP_REMOTE_URL:-https://github.com/${OWNER}/${repo}.git}"
  # 1) لقطة البيانات من API + تحقق صلاحيتها
  if ! gh api "repos/$OWNER/$repo/pulls/$pr" > "$mf" 2>/dev/null; then
    log "فشل النسخ الاحتياطي لـ$repo#$pr — تعذر جلب بيانات الـPR من API"; return 1
  fi
  if ! python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("number") == int(sys.argv[2]), "رقم PR غير مطابق"
assert d.get("head", {}).get("sha"), "sha الرأس مفقود"
assert d.get("title"), "العنوان مفقود"
' "$mf" "$pr" 2>/dev/null; then
    log "فشل النسخ الاحتياطي لـ$repo#$pr — ملف البيانات فارغ أو غير صالح"; return 1
  fi
  local sha
  sha=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["head"]["sha"])' "$mf")
  # 2) bundle مستقل: جلب الرأس إلى مستودع عمل مؤقت ثم تغليفه
  local w="$PWD/.bk_scratch_$$" r="$PWD/.bk_restore_$$" v="$PWD/.bk_verify_$$"
  rm -rf "$w" "$r" "$v"; mkdir -p "$w"
  # مصادقة بلا توكن في العنوان أو وسائط العملية (جولة 3): سكربت askpass مؤقت
  # يقرأ GH_TOKEN من البيئة عند سؤال git — لا قيمة سرية في العنوان ولا الوسائط —
  # ويُحذف مع مستودع العمل فور انتهاء الجلب والتغليف.
  cat > "$w/.askpass" <<'ASKPASS'
#!/bin/sh
# مؤقت — المصادقة من البيئة (GH_TOKEN) لا من عنوان URL ولا من وسائط العملية
case "$1" in
  Username*) printf 'x-access-token\n' ;;
  *)         printf '%s\n' "${GH_TOKEN:?missing}" ;;
esac
ASKPASS
  chmod 700 "$w/.askpass"
  if ! git -C "$w" init -q \
     || ! GIT_ASKPASS="$w/.askpass" GIT_TERMINAL_PROMPT=0 git -C "$w" fetch -q "$remote" "${sha}:refs/heads/backup" \
     || ! git -C "$w" bundle create "$PWD/$bf" refs/heads/backup; then
    log "فشل النسخ الاحتياطي لـ$repo#$pr — تعذر إنشاء git bundle للرأس ${sha:0:7}"
    rm -rf "$w"; return 1
  fi
  rm -rf "$w"   # حذف askpass ومستودع العمل فور انتهاء الجلب والتغليف
  # 3) تحقق الاستعادة: verify من مستودع فارغ (لا متطلبات مسبقة) + استنساخ فعلي
  mkdir -p "$v"
  if git -C "$v" init -q && git -C "$v" bundle verify "$PWD/$bf" > /dev/null 2>&1; then :; else
    log "فشل النسخ الاحتياطي لـ$repo#$pr — git bundle verify رفض الملف"
    rm -rf "$w" "$v"; return 1
  fi
  if ! git clone -q "$PWD/$bf" "$r" 2>/dev/null \
     || ! git -C "$r" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    log "فشل النسخ الاحتياطي لـ$repo#$pr — الاستعادة من الـbundle لم تثبت"
    rm -rf "$w" "$r" "$v"; return 1
  fi
  rm -rf "$w" "$r" "$v"
  echo "$repo#$pr $sha $tag $(date -Iseconds) bundle=$bf size=$(stat -c%s "$bf")" >> "backups/backup_manifest.tsv"
  if ! run git -C "$repo" tag "$tag" "$sha" 2>/dev/null; then
    log "  (وسم محلي $tag لم يُنشأ — لا يمنع الدمج؛ المعتمد: manifest + pr_meta + bundle)"
  fi
  log "نسخة احتياطية مستقلة مؤكدة: $repo#$pr @ ${sha:0:7} → $bf (استعادة مُثبتة) + $mf"
}

# ── تحقق مستقل من GitHub الحي قبل أي MERGED: closed + merged=true + sha ──
verify_merged() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  local f="backups/merge_confirm_${repo}_${pr}.json"
  if ! gh api "repos/$OWNER/$repo/pulls/$pr" > "$f" 2>/dev/null; then
    log "توقف $repo#$pr — تعذر جلب الحالة الحية للتحقق بعد الدمج"; return 1
  fi
  local verdict
  verdict=$(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
ok = (d.get("merged") is True and d.get("state") == "closed" and bool(d.get("merge_commit_sha")))
print(("OK " + str(d.get("merge_commit_sha"))[:7]) if ok else "BAD")
' "$f" 2>/dev/null) || verdict="BAD"
  if [ "${verdict%% *}" = "OK" ]; then
    log "تأكيد حي: $repo#$pr merged=true sha=${verdict#* }"
    return 0
  fi
  log "GitHub الحي لا يؤكد الدمج ($verdict)"; return 1
}

merge_pr() { # $1=repo $2=pr_number $3=head_branch (يُقبل للتوافق ولا يُستخدم — sha من API) $4=طريقة الدمج (merge|squash)
  local repo="$1" pr="$2" method="${4:-merge}"
  premerge_gate "$repo" "$pr" || { log "توقف $repo#$pr — رفض بوابة ما قبل الدمج"; return 1; }
  backup_pr "$repo" "$pr" || { log "توقف $repo#$pr — فشل النسخ الاحتياطي: لا دمج (fail-closed)"; return 1; }
  if ! run gh pr merge --repo "$OWNER/$repo" "$pr" --"$method" --delete-branch=false; then
    log "توقف $repo#$pr — فشل أمر الدمج؛ لا يُسجل MERGED"
    return 1
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "MERGED (محاكاة DRY-RUN — بلا تنفيذ): $repo#$pr ($method)"
    return 0
  fi
  if verify_merged "$repo" "$pr"; then
    log "MERGED $repo#$pr ($method) — مؤكد من حالة GitHub الحية"
  else
    log "توقف $repo#$pr — أمر الدمج عاد صفرًا لكن GitHub الحي لا يؤكد؛ يُسجل توقفًا لا MERGED"
    return 1
  fi
}

# ── تحقق حي من الإغلاق (جولة 2 — كانت تسجل CLOSED دون فحص) ──
verify_closed() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  local f="backups/close_confirm_${repo}_${pr}.json"
  if ! gh api "repos/$OWNER/$repo/pulls/$pr" > "$f" 2>/dev/null; then
    log "توقف إغلاق $repo#$pr — تعذر جلب الحالة الحية للتحقق"; return 1
  fi
  local verdict
  verdict=$(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
# حالة PR من API بالأحرف الصغيرة: open | closed
print("OK" if d.get("state") == "closed" else "BAD")
' "$f" 2>/dev/null) || verdict="BAD"
  if [ "$verdict" = "OK" ]; then log "تأكيد حي: $repo#$pr state=CLOSED"; return 0; fi
  log "GitHub الحي لا يؤكد الإغلاق ($verdict)"; return 1
}

close_pr() { # $1=repo $2=pr_number $3+=سبب بالعربية — لا CLOSED إلا بتحقق حي؛ DRY_RUN لا يدعي نجاحًا
  local repo="$1" pr="$2"; shift 2
  local reason="$*"
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN (لن يُنفذ): إغلاق $repo#$pr — $reason (لا يُسجل CLOSED)"
    return 0
  fi
  if ! run gh pr close --repo "$OWNER/$repo" "$pr" --comment "الإغلاق بقرار موثق من المالك: $reason"; then
    log "توقف إغلاق $repo#$pr — فشل الأمر؛ لا يُسجل CLOSED"
    return 1
  fi
  if verify_closed "$repo" "$pr"; then
    log "CLOSED $repo#$pr — $reason (مؤكد من حالة GitHub الحية)"
  else
    log "توقف إغلاق $repo#$pr — الأمر عاد صفرًا لكن GitHub الحي لا يؤكد؛ يُسجل توقفًا لا CLOSED"
    return 1
  fi
}
