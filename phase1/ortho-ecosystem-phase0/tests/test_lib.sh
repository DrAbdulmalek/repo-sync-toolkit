#!/usr/bin/env bash
# test_lib.sh — اختبارات سلبية/إيجابية لبوابات lib.sh بمحاكاة gh كاملة
# لا شبكة، لا توكن حقيقي. غيّر البيانات عبر متغيرات MOCK_* داخل كل سيناريو.
# التغطية (طلب مراجعة المالك 2026-11-23):
#   T1 فشل أمر الدمج            → لا MERGED + رمز خروج غير صفري
#   T2 فشل جلب النسخة (API)     → لا دمج نهائيًا (fail-closed)
#   T3 نسخة فارغة/غير صالحة     → لا دمج نهائيًا (fail-closed)
#   T4 فشل الوسم المحلي         → لا يمنع الدمج (النسخة المعتمدة manifest+JSON) — موثق
#   T5 CI معلق                 → البوابة ترفض
#   T6 بلا فحوص                → البوابة ترفض
#   T7 دمج مزيف (exit 0 مع PR مفتوح) → لا MERGED — التحقق من الحالة الحية يكشفه
#   T8 المسار السليم            → MERGED مع sha مؤكد حيًا
#   T9 DRY_RUN=1               → لا تنفيذ ولا ادعاء MERGED حقيقي
# تعطيلات مقصودة: تلوث متغيرات subshells عمدًا للعزل + تصدير ديناميكي لخيارات
# السيناريو + مصدر lib غير ثابت النسبي — كلها قرار تصميمي في حزمة الاختبار
# shellcheck disable=SC2030,SC2031,SC2163,SC1090
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib.sh"
PASS=0; FAIL=0

# JSON الـPR الذي يرجعه gh api الوهمي (يغطي النسخة الاحتياطية والتحقق معًا)
pr_json() { # $1=state $2=merged $3=sha
  printf '{"number":77,"title":"test pr","state":"%s","merged":%s,"merge_commit_sha":"%s","head":{"sha":"deadbeef1234567890","ref":"feat/x"}}' "$1" "$2" "$3"
}

setup_sandbox() { # $@ = أوامر إعداد إضافية (غير مستخدمة حاليًا)
  SB="$(mktemp -d /tmp/libtest.XXXXXX)"
  MOCKDIR="$SB/mockbin"
  mkdir -p "$MOCKDIR"
  cat > "$MOCKDIR/gh" <<'MOCK'
#!/usr/bin/env bash
# gh وهمي — سلوكه يتحكم فيه: MOCK_MERGE (ok|fail) MOCK_API (ok|err|garbage)
# MOCK_LIE (1: الدمج exit 0 لكن الحالة تبقى مفتوحة) MOCK_CHECKS (ok|pending|fail|none)
pr_json() { # $1=state $2=merged $3=sha — JSON واحد يغطي النسخة الاحتياطية والتحقق
  printf '{"number":77,"title":"test pr","state":"%s","merged":%s,"merge_commit_sha":"%s","head":{"sha":"deadbeef1234567890","ref":"feat/x"}}' "$1" "$2" "$3"
}
case "$1" in
  auth) exit 0 ;;
  pr)
    case "$2" in
      view) printf '{"state":"OPEN","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":""}'; exit 0 ;;
      checks)
        case "${MOCK_CHECKS:-ok}" in
          ok) exit 0 ;;
          pending) exit 8 ;;
          fail|none) exit 1 ;;
          *) exit 1 ;;
        esac ;;
      merge)
        if [ "${MOCK_MERGE:-ok}" = "fail" ]; then
          echo "X Pull request is not mergeable: simulated failure" >&2; exit 1
        fi
        exit 0 ;;
      *) exit 0 ;;
    esac ;;
  api)
    if [ "${MOCK_API:-ok}" = "err" ]; then
      echo "gh: api error (simulated)" >&2; exit 1
    fi
    if [ "${MOCK_API:-ok}" = "garbage" ]; then printf 'not-json-empty'; exit 0; fi
    if [ "${MOCK_LIE:-0}" = "1" ]; then pr_json open false ""; else pr_json closed true "mergedsha0000000000000000000000000aa"; fi
    exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$MOCKDIR/gh"
}

run_scenario() { # $1=اسم السيناريو — يهيئ sandbox جديدًا ثم ينفذ البلوك الممرر
  setup_sandbox
  ( cd "$SB" \
      && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" \
      && export "$@" \
      && export DRY_RUN=0 \
      && source "$LIB" \
      && merge_pr "medical-ocr-trainer" 77 "feat/x" merge ) > "$SB/out.txt" 2>&1
  RC=$?
  LOG=$(find "$SB/logs" -name '*.log' 2>/dev/null | head -1)
  LOGTXT=$(cat "$LOG" 2>/dev/null || true)
}

expect() { # $1=شرح $2=شرط (0/1)
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}
has()    { [ "${LOGTXT#*"$1"}" != "${LOGTXT}" ] && echo 0 || echo 1; }  # يحتوي النص
lacks()  { [ "${LOGTXT#*"$1"}" = "${LOGTXT}" ] && echo 0 || echo 1; }  # لا يحتويه

echo "═══ T1: فشل أمر الدمج → لا MERGED ═══"
run_scenario MOCK_MERGE=fail MOCK_API=ok
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق فشل أمر الدمج" "$(has "فشل أمر الدمج")"
expect "لا يحتوي MERGED نهائيًا" "$(lacks "MERGED $")"
expect "لا يحتوي مؤكد من حالة GitHub" "$(lacks "مؤكد من حالة")"

echo "═══ T2: فشل جلب النسخة من API → لا دمج نهائيًا ═══"
run_scenario MOCK_MERGE=ok MOCK_API=err
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق فشل النسخ الاحتياطي" "$(has "فشل النسخ الاحتياطي")"
expect "أمر الدمج لم يُحاول أصلًا" "$(lacks "gh pr merge")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T3: نسخة فارغة/غير صالحة → لا دمج نهائيًا ═══"
run_scenario MOCK_MERGE=ok MOCK_API=garbage
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق ملف غير صالح" "$(has "فارغ أو غير صالح")"
expect "أمر الدمج لم يُحاول أصلًا" "$(lacks "gh pr merge")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T4: فشل الوسم المحلي → الدمج يستمر (النسخة المعتمدة manifest+JSON) ═══"
run_scenario MOCK_MERGE=ok MOCK_API=ok
expect "رمز خروج صفري" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "الوسم موثق كغير مانع" "$(has "لا يمنع الدمج")"
expect "MERGED مع تأكيد حي" "$(has "مؤكد من حالة GitHub الحية")"
expect "sha مؤكد موجود في السجل" "$(has "sha=mergeds")"

echo "═══ T5: CI معلق → البوابة ترفض ═══"
run_scenario MOCK_CHECKS=pending MOCK_MERGE=ok MOCK_API=ok
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض CI" "$(has "رفض: CI غير أخضر")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T6: بلا فحوص → البوابة ترفض ═══"
run_scenario MOCK_CHECKS=none MOCK_MERGE=ok MOCK_API=ok
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض CI" "$(has "رفض: CI غير أخضر")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T7: دمج مزيف (exit 0 والحالة مفتوحة) → لا MERGED ═══"
run_scenario MOCK_LIE=1 MOCK_MERGE=ok MOCK_API=ok
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يكشف عدم التأكيد الحي" "$(has "GitHub الحي لا يؤكد")"
expect "لا MERGED حقيقي" "$(lacks "مؤكد من حالة")"

echo "═══ T8: المسار السليم → MERGED مؤكد حيًا ═══"
run_scenario MOCK_MERGE=ok MOCK_API=ok
expect "رمز خروج صفري" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "نسخة احتياطية مؤكدة في السجل" "$(has "نسخة احتياطية مؤكدة")"
expect "ملف النسخة غير فارغ" "$([ -s "$SB/backups/pr_medical-ocr-trainer_77.json" ] && echo 0 || echo 1)"
expect "manifest يحوي sha الرأس" "$(grep -q "deadbeef1234" "$SB/backups/backup_manifest.tsv" && echo 0 || echo 1)"
expect "ملف تأكيد الدمج موجود وصالح" "$(python3 -I -c "import json;d=json.load(open('$SB/backups/merge_confirm_medical-ocr-trainer_77.json'));assert d['merged'] is True" 2>/dev/null && echo 0 || echo 1)"
expect "MERGED مع مؤكد حي" "$(has "مؤكد من حالة GitHub الحية")"

echo "═══ T9: DRY_RUN=1 → لا تنفيذ ولا ادعاء MERGED حقيقي ═══"
setup_sandbox
( cd "$SB" \
    && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" DRY_RUN=1 \
    && source "$LIB" \
    && merge_pr "medical-ocr-trainer" 77 "feat/x" merge ) > "$SB/out.txt" 2>&1
RC=$?
LOGTXT=$(cat "$SB"/logs/*.log 2>/dev/null || true)
expect "رمز خروج صفري (محاكاة)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "الأمر لم يُنفذ" "$(has "DRY-RUN (لن يُنفذ)")"
expect "MERGED موسوم محاكاة فقط" "$(has "محاكاة DRY-RUN — بلا تنفيذ")"
expect "لا ادعاء تأكيد حي" "$(lacks "مؤكد من حالة GitHub الحية")"

echo
echo "═══ الخلاصة: نجح $PASS / فشل $FAIL ═══"
[ $FAIL -eq 0 ] || exit 1
