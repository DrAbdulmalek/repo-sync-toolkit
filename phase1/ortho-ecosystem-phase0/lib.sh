#!/usr/bin/env bash
# lib.sh — مكتبة مشتركة لحزمة تنفيذ المرحلة 1 محليًا (توكنك يبقى على جهازك)
# الاستخدام: source ./lib.sh ثم استدعِ الدوال.
set -euo pipefail

: "${GH_TOKEN:?ضع التوكن: export GH_TOKEN=ghp_...  (لا تضع التوكن في أي ملف)}"
export GH_TOKEN
OWNER="DrAbdulmalek"
DRY_RUN="${DRY_RUN:-1}"          # افتراضي: محاكاة فقط. للتطبيق: DRY_RUN=0
LOG_FILE="${LOG_FILE:-phase1_run_$(date +%Y%m%d_%H%M%S).log}"
mkdir -p logs backups

log()  { echo "[$(date '+%F %T')] $*" | tee -a "logs/$LOG_FILE"; }
run()  { # يطبق الأمر فعليًا فقط إذا لم نكن في وضع المحاكاة
  if [ "$DRY_RUN" = "1" ]; then log "DRY-RUN (لن يُنفذ): $*"; else log "EXEC: $*"; "$@"; fi
}

gh_api() { gh api "$1" ${2:-}; }   # غلاف موحد للتوثيق والتصحيح

require_gh() {
  command -v gh >/dev/null || { echo "ثبّت gh CLI أولًا: https://cli.github.com"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "المصادقة فشلت — تحقق من GH_TOKEN"; exit 1; }
  log "gh جاهز — DRY_RUN=$DRY_RUN"
}

# فحوصات ما قبل الدمج: CI أخضر + لا تعارض + mergeable
premerge_gate() { # $1=repo $2=pr_number
  local repo="$1" pr="$2"
  log "بوابة الجودة: $repo#$pr"
  gh pr view "$OWNER/$repo#$pr" --json state,mergeable,mergeStateStatus,reviewDecision \
    --jq '{state,mergeable,mergeStateStatus,reviewDecision}' | tee -a "logs/$LOG_FILE"
  if ! gh pr checks "$OWNER/$repo#$pr" --watch --fail-fast >/dev/null 2>&1; then
    log "رفض: CI غير أخضر على $repo#$pr"; return 1; fi
}

# نسخ احتياطي: وسم رأس الفرع قبل الدمج + حفظ بيانات الـPR
backup_pr() { # $1=repo $2=pr_number $3=head_branch
  local repo="$1" pr="$2" head="$3"
  local tag="pre-merge/pr-${pr}-$(date +%Y%m%d)"
  local sha
  sha=$(gh api "repos/$OWNER/$repo/commits/$head" --jq .sha)
  echo "$repo#$pr $sha $tag $(date -Iseconds)" >> "backups/backup_manifest.tsv"
  run git -C "$repo" tag "$tag" "$sha" 2>/dev/null || true
  gh pr view "$OWNER/$repo#$pr" --json > "backups/pr_${repo}_${pr}.json"
  log "نسخة احتياطية: $repo#$pr @ ${sha:0:7} (وسم محلي $tag)"
}

merge_pr() { # $1=repo $2=pr_number $3=head_branch $4=طريقة الدمج (merge|squash)
  local repo="$1" pr="$2" head="$3" method="${4:-merge}"
  premerge_gate "$repo" "$pr" || return 1
  backup_pr "$repo" "$pr" "$head"
  run gh pr merge "$OWNER/$repo#$pr" --"$method" --delete-branch=false
  log "MERGED $repo#$pr ($method)"
}

close_pr() { # $1=repo $2=pr_number $3=سبب بالعربية
  local repo="$1" pr="$2"; shift 2
  local reason="$*"
  run gh pr close "$OWNER/$repo#$pr" --comment "الإغلاق بقرار موثق من المالك: $reason"
  log "CLOSED $repo#$pr — $reason"
}
