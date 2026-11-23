#!/usr/bin/env bash
# lib.sh — مكتبة مشتركة لحزمة تنفيذ المرحلة 1 محليًا (توكنك يبقى على جهازك)
# الاستخدام: source ./lib.sh ثم استدعِ الدوال.
#
# إصلاحات 2026-11-23 (بعد مراجعة المالك — الثغرتان المغلقتان هنا):
#   1) مسار MERGED الكاذب مغلق: merge_pr لا يسجل MERGED إلا بعد فحص الحالة الحية
#      (state=closed + merged=true + merge_commit_sha) من GitHub نفسه، وليس من
#      رمز خروج الأمر وحده.
#   2) النسخة الاحتياطية بوابة فعلية: تُجلب من API موثوق وتُتحقق (غير فارغ +
#      JSON صالح + رقم PR مطابق + sha رأس موجود) — وفشلها يمنع الدمج نهائيًا.
#   3) صيغة gh v2.105: --repo OWNER/REPO NUM بدل OWNER/REPO#NUM.
#   4) فحص CI لحظي واحد (بدل --watch): نفس البوابة fail-closed؛ المعلق يُسجل
#      ويُعاد في نهاية الجولة — لا انتظار حي.
#   5) run() يوثق الفشل بصدق (EXEC-FAILED) ويعود برمز خروج غير صفري.
set -euo pipefail

: "${GH_TOKEN:?ضع التوكن: export GH_TOKEN=ghp_...  (لا تضع التوكن في أي ملف)}"
export GH_TOKEN
OWNER="DrAbdulmalek"
DRY_RUN="${DRY_RUN:-1}"          # افتراضي: محاكاة فقط. للتطبيق: DRY_RUN=0
LOG_FILE="${LOG_FILE:-phase1_run_$(date +%Y%m%d_%H%M%S).log}"
mkdir -p logs backups

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

# فحوصات ما قبل الدمج: CI أخضر + لا تعارض + mergeable (fail-closed)
premerge_gate() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  log "بوابة الجودة: $repo#$pr"
  gh pr view --repo "$OWNER/$repo" "$pr" --json state,mergeable,mergeStateStatus,reviewDecision \
    --jq '{state,mergeable,mergeStateStatus,reviewDecision}' | tee -a "logs/$LOG_FILE"
  # فحص لحظي واحد (بدل --watch): المعلق/الفاشل/البلا-فحوص يُرفض جميعًا — fail-closed
  if ! gh pr checks --repo "$OWNER/$repo" "$pr" >/dev/null 2>&1; then
    log "رفض: CI غير أخضر (أو معلق/بلا فحوص) على $repo#$pr"; return 1; fi
}

# النسخة الاحتياطية بوابة: تُجلب من API وتُتحقق — فشلها يمنع الدمج نهائيًا.
# الوسم المحلي استعاضة تجميلية فقط ولا يدخل في قرار الدمج (المعتمد: manifest + JSON حي).
backup_pr() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  local tag
  tag="pre-merge/pr-${pr}-$(date +%Y%m%d)"
  local f="backups/pr_${repo}_${pr}.json"
  if ! gh api "repos/$OWNER/$repo/pulls/$pr" > "$f" 2>/dev/null; then
    log "فشل النسخ الاحتياطي لـ$repo#$pr — تعذر جلب بيانات الـPR من API"; return 1
  fi
  if ! python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("number") == int(sys.argv[2]), "رقم PR غير مطابق"
assert d.get("head", {}).get("sha"), "sha الرأس مفقود"
assert d.get("title"), "العنوان مفقود"
' "$f" "$pr" 2>/dev/null; then
    log "فشل النسخ الاحتياطي لـ$repo#$pr — الملف فارغ أو غير صالح"; return 1
  fi
  local sha
  sha=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["head"]["sha"])' "$f")
  echo "$repo#$pr $sha $tag $(date -Iseconds)" >> "backups/backup_manifest.tsv"
  if ! run git -C "$repo" tag "$tag" "$sha" 2>/dev/null; then
    log "  (وسم محلي $tag لم يُنشأ — لا يمنع الدمج؛ النسخة المعتمدة: manifest + JSON)"
  fi
  log "نسخة احتياطية مؤكدة: $repo#$pr @ ${sha:0:7} → $f"
}

# تحقق مستقل من GitHub الحي قبل أي MERGED: state=closed + merged=true + sha موجود
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

merge_pr() { # $1=repo $2=pr_number $3=head_branch (يُقبل للتوافق مع المستدعين ولا يُستخدم — sha يأتي من API) $4=طريقة الدمج (merge|squash)
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

close_pr() { # $1=repo $2=pr_number $3=سبب بالعربية
  local repo="$1" pr="$2"; shift 2
  local reason="$*"
  run gh pr close --repo "$OWNER/$repo" "$pr" --comment "الإغلاق بقرار موثق من المالك: $reason"
  log "CLOSED $repo#$pr — $reason"
}
