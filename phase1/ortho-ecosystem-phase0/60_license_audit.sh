#!/usr/bin/env bash
# 60_license_audit.sh — بعد كل دفعة: تدقيق التراخيص على كامل الحساب (يجب أن يخرج 0)
set -euo pipefail
source ./lib.sh
require_gh

mkdir -p license_scan && cd license_scan
[ -d repo-sync-toolkit ] || git clone --depth 1 "https://github.com/$OWNER/repo-sync-toolkit.git"
cd repo-sync-toolkit
git pull --ff-only 2>/dev/null || true
if [ -f license_audit.py ]; then
  python3 license_audit.py || log "⚠️ license_audit خرج nonzero — راجع المخالفات أعلاه"
else
  log "⚠️ license_audit.py غير موجود في repo-sync-toolkit — ادمج PR #12 أولًا (الفئة ب)"
fi
# تقرير NOASSERTION الحي من API
gh api "users/$OWNER/repos?per_page=100" --jq '.[] | select(.license.spdx_id=="NOASSERTION" or .license==null) | .name' > ../noassertion_live.txt || true
log "NOASSERTION الحي: $(cat ../noassertion_live.txt | tr '\n' ' ')"
log "انتهى تدقيق التراخيص"
