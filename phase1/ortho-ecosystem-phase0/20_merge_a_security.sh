#!/usr/bin/env bash
# 20_merge_a_security.sh — الفئة أ: الـPRs الأمنية (دمج أولًا، P0)
# كل PR: بوابة CI أخضر → نسخة احتياطية → دمج. DRY_RUN=1 افتراضيًا (محاكاة فقط).
set -euo pipefail
source ./lib.sh
require_gh

SECURITY_PRS=(
  "omni-medical-suite 201 fix(security): remove python-jose (PYSEC-2026-4298)"
  "omni-medical-suite 102 harden snapshot exporter against path/symlink escapes"
  "omni-medical-suite 90  security fixes: separator, admin auth, deployment"
  "omni-medical-suite 86  close post-85 deployment and condition-parser gaps"
  "omni-medical-suite 132 HF upload OFF by default + de-identification"
  "omni-medical-suite 131 SEC-2 env token-shape guard"
  "omni-medical-suite 130 quarantine Telegram Forwarder"
)

for entry in "${SECURITY_PRS[@]}"; do
  set -- $entry; repo=$1; pr=$2; shift 2; title="$*"
  log "=== الفئة أ: $repo#$pr — $title"
  head=$(gh pr view --repo "$OWNER/$repo" "$pr" --json headRefName --jq .headRefName)
  merge_pr "$repo" "$pr" "$head" merge || log "توقف $repo#$pr — راجع سجل البوابة"
done

# بند التحقق الأمني المستعرض: غياب أي token/سر في query strings (نمط WP-01-A)
log "=== الفحص المستعرض: أسرار في query strings عبر كل المستودعات الأساسية"
for repo in omni-medical-suite intelli-file-manager ocr-core OmniFile_Processor scanner-fixer medical-rag-ar marathon-suite translation-core; do
  mkdir -p "scan/$repo"
  git clone --depth 1 "https://github.com/$OWNER/$repo.git" "scan/$repo" 2>/dev/null || true
  if [ -d "scan/$repo" ]; then
    grep -rInE '(token|secret|api[_-]?key|password)=[^"& ]+' "scan/$repo/src" 2>/dev/null \
      | tee -a "logs/$LOG_FILE" || log "  $repo: نظيف"
  fi
done
log "انتهت الفئة أ"
