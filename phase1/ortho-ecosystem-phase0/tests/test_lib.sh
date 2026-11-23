#!/usr/bin/env bash
# test_lib.sh — اختبارات سلبية/إيجابية لبوابات lib.sh بمحاكاة gh كاملة + git حقيقي
# لا شبكة، لا توكن حقيقي. غيّر البيانات عبر متغيرات MOCK_* داخل كل سيناريو.
# التغطية (جولة مراجعة المالك الثانية 2026-11-23):
#   T1  فشل أمر الدمج               → لا MERGED + رمز خروج غير صفري
#   T2  فشل جلب البيانات (API)      → لا دمج نهائيًا (fail-closed)
#   T3  لقطة بيانات غير صالحة       → لا دمج نهائيًا (fail-closed)
#   T4  فشل الوسم المحلي            → لا يمنع الدمج (المعتمد: manifest+meta+bundle)
#   T5  CI معلق                    → البوابة ترفض
#   T6  بلا فحوص                   → البوابة ترفض
#   T7  دمج مزيف (exit 0 والحالة تبقى مفتوحة) → التحقق الحي يكشفه
#   T8  انتقال الحالة OPEN→MERGED   → لقطة البيانات قبل = open، التأكيد بعد = merged،
#                                   bundle موجود ومستعاد، MERGED بشهادة حية
#   T9  DRY_RUN=1                  → لا تنفيذ ولا ادعاء MERGED حقيقي
#   T10 تعارض DIRTY/CONFLICTING    → البوابة ترفض قبل أي أمر دمج
#   T11 حالة دمج BLOCKED           → البوابة ترفض
#   T12 مراجعة CHANGES_REQUESTED   → البوابة ترفض
#   T13 PR مغلق/مدموج مسبقًا       → البوابة ترفض قبل محاولة الدمج
#   T14 mergeable=UNKNOWN          → البوابة ترفض (القيم المجهولة)
#   T15 حالة دمج BEHIND            → البوابة ترفض
#   T16 فشل إنشاء bundle           → لا دمج نهائيًا (النسخة المستقلة شرط)
#   T17 إغلاق ناجح                 → CLOSED مؤكد حيًا فقط
#   T18 فشل الإغلاق                → لا CLOSED
#   T19 إغلاق في DRY_RUN           → لا ادعاء CLOSED أصلًا
# تعطيلات مقصودة: تلوث متغيرات subshells عمدًا للعزل + تصدير ديناميكي لخيارات
# السيناريو + مصدر lib غير ثابت النسبي — كلها قرار تصميمي في حزمة الاختبار
# shellcheck disable=SC2030,SC2031,SC2163,SC1090
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib.sh"
PASS=0; FAIL=0

setup_sandbox() {
  SB="$(mktemp -d /tmp/libtest.XXXXXX)"
  MOCKDIR="$SB/mockbin"
  mkdir -p "$MOCKDIR"
  cat > "$MOCKDIR/gh" <<'MOCK'
#!/usr/bin/env bash
# gh وهمي — انتقال حالة عبر ملف حالة (phase=before|after|closed-pr) لكي ترى
# كل مرحلة استجابة مختلفة: قبل الدمج مفتوح، بعد الدمج الناجح مدموج، بعد الإغلاق مغلق.
# متحكمات: MOCK_CHECKS(ok|pending|fail|none) MOCK_MERGE(ok|fail) MOCK_CLOSE(ok|fail)
# MOCK_API(ok|err|garbage) MOCK_LIE(1) MOCK_GATE(ok|dirty|blocked|changes|unknown|behind|closed)
SF="${MOCK_STATE_FILE:?}"
sf_val() { local k="$1" v="" a b; while IFS='=' read -r a b; do [ "$a" = "$k" ] && v="$b"; done < "$SF"; printf '%s' "$v"; }
pr_json() { # حسب الطور الحالي لملف الحالة
  local sha; sha=$(sf_val sha)
  case "$(sf_val phase)" in
    after)     printf '{"number":77,"title":"test pr","state":"closed","merged":true,"merge_commit_sha":"%s","head":{"sha":"%s","ref":"feat/x"}}' "$(sf_val merge)" "$sha" ;;
    closed-pr) printf '{"number":77,"title":"test pr","state":"closed","merged":false,"merge_commit_sha":null,"head":{"sha":"%s","ref":"feat/x"}}' "$sha" ;;
    *)         printf '{"number":77,"title":"test pr","state":"open","merged":false,"merge_commit_sha":null,"head":{"sha":"%s","ref":"feat/x"}}' "$sha" ;;
  esac
}
case "$1" in
  auth) exit 0 ;;
  pr)
    case "$2" in
      view)
        case "${MOCK_GATE:-ok}" in
          ok)      printf '{"state":"OPEN","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":null}'; exit 0 ;;
          dirty)   printf '{"state":"OPEN","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":null}'; exit 0 ;;
          blocked) printf '{"state":"OPEN","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":null}'; exit 0 ;;
          changes) printf '{"state":"OPEN","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"CHANGES_REQUESTED"}'; exit 0 ;;
          unknown) printf '{"state":"OPEN","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN","reviewDecision":null}'; exit 0 ;;
          behind)  printf '{"state":"OPEN","mergeable":"MERGEABLE","mergeStateStatus":"BEHIND","reviewDecision":null}'; exit 0 ;;
          closed)  printf '{"state":"MERGED","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":null}'; exit 0 ;;
          *) exit 1 ;;
        esac ;;
      checks)
        case "${MOCK_CHECKS:-ok}" in
          ok) exit 0 ;;
          pending) exit 8 ;;
          *) exit 1 ;;
        esac ;;
      merge)
        if [ "${MOCK_MERGE:-ok}" = "fail" ]; then echo "X not mergeable (simulated)" >&2; exit 1; fi
        if [ "${MOCK_LIE:-0}" != "1" ]; then sed -i 's/^phase=.*/phase=after/' "$SF"; fi
        exit 0 ;;
      close)
        if [ "${MOCK_CLOSE:-ok}" = "fail" ]; then echo "X close failed (simulated)" >&2; exit 1; fi
        sed -i 's/^phase=.*/phase=closed-pr/' "$SF"; exit 0 ;;
      *) exit 0 ;;
    esac ;;
  api)
    case "${MOCK_API:-ok}" in
      err) echo "gh: api error (simulated)" >&2; exit 1 ;;
      garbage) printf 'not-json-empty'; exit 0 ;;
      *) pr_json; exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$MOCKDIR/gh"
  # مستودع أصل حقيقي محلي: fetch-by-sha + bundle + استعادة فعلية بأوامر git حقيقية
  git init -q "$SB/origin"
  git -C "$SB/origin" config user.email t@t
  git -C "$SB/origin" config user.name t
  echo "source" > "$SB/origin/file.txt"
  git -C "$SB/origin" add file.txt
  git -C "$SB/origin" commit -qm "head commit"
  git -C "$SB/origin" config uploadpack.allowReachableSHA1InWant true
  ORIGIN_SHA="$(git -C "$SB/origin" rev-parse HEAD)"
  printf 'phase=before\nsha=%s\nmerge=mergedsha0000000000000000000000000aa\n' "$ORIGIN_SHA" > "$SB/state"
}

# يشغّل merge_pr في sandbox معزول؛ "$@" خيارات MOCK_* للسيناريو
run_scenario() {
  setup_sandbox
  ( cd "$SB" \
      && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" \
      && export DRY_RUN=0 MOCK_STATE_FILE="$SB/state" BACKUP_REMOTE_URL="$SB/origin" \
      && export "$@" \
      && source "$LIB" \
      && merge_pr "medical-ocr-trainer" 77 "feat/x" merge ) > "$SB/out.txt" 2>&1
  RC=$?
  LOG=$(find "$SB/logs" -name '*.log' 2>/dev/null | head -1)
  LOGTXT=$(cat "$LOG" 2>/dev/null || true)
}

# يشغّل close_pr في sandbox معزول؛ "$@" خيارات MOCK_* للسيناريو
run_close_scenario() {
  setup_sandbox
  ( cd "$SB" \
      && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" \
      && export "$@" \
      && export DRY_RUN=0 MOCK_STATE_FILE="$SB/state" \
      && source "$LIB" \
      && close_pr "medical-ocr-trainer" 77 "سبب تجريبي" ) > "$SB/out.txt" 2>&1
  RC=$?
  LOG=$(find "$SB/logs" -name '*.log' 2>/dev/null | head -1)
  LOGTXT=$(cat "$LOG" 2>/dev/null || true)
}

expect() { # $1=شرح $2=شرط (0/1)
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}
has()    { [ "${LOGTXT#*"$1"}" != "${LOGTXT}" ] && echo 0 || echo 1; }  # السجل يحتوي النص
lacks()  { [ "${LOGTXT#*"$1"}" = "${LOGTXT}" ] && echo 0 || echo 1; }  # السجل لا يحتويه

echo "═══ T1: فشل أمر الدمج → لا MERGED ═══"
run_scenario MOCK_MERGE=fail
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق فشل أمر الدمج" "$(has "فشل أمر الدمج")"
expect "لا يحتوي MERGED نهائيًا" "$(lacks "MERGED $")"
expect "لا يحتوي مؤكد من حالة GitHub" "$(lacks "مؤكد من حالة")"

echo "═══ T2: فشل جلب البيانات من API → لا دمج نهائيًا ═══"
run_scenario MOCK_MERGE=ok MOCK_API=err
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق فشل النسخ الاحتياطي" "$(has "فشل النسخ الاحتياطي")"
expect "أمر الدمج لم يُحاول أصلًا" "$(lacks "gh pr merge")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T3: لقطة بيانات غير صالحة → لا دمج نهائيًا ═══"
run_scenario MOCK_MERGE=ok MOCK_API=garbage
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق ملف غير صالح" "$(has "فارغ أو غير صالح")"
expect "أمر الدمج لم يُحاول أصلًا" "$(lacks "gh pr merge")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T4: فشل الوسم المحلي → الدمج يستمر (المعتمد: manifest+meta+bundle) ═══"
run_scenario MOCK_MERGE=ok
expect "رمز خروج صفري" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "الوسم موثق كغير مانع" "$(has "لا يمنع الدمج")"
expect "نسخة مستقلة مؤكدة في السجل" "$(has "نسخة احتياطية مستقلة مؤكدة")"
expect "MERGED مع تأكيد حي" "$(has "مؤكد من حالة GitHub الحية")"
expect "sha حي في السجل" "$(has "sha=mergeds")"

echo "═══ T5: CI معلق → البوابة ترفض ═══"
run_scenario MOCK_CHECKS=pending
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض CI" "$(has "رفض: CI غير أخضر")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T6: بلا فحوص → البوابة ترفض ═══"
run_scenario MOCK_CHECKS=none
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض CI" "$(has "رفض: CI غير أخضر")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T7: دمج مزيف (exit 0 والحالة تبقى مفتوحة) → لا MERGED ═══"
run_scenario MOCK_LIE=1
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يكشف عدم التأكيد الحي" "$(has "GitHub الحي لا يؤكد")"
expect "لا MERGED حقيقي" "$(lacks "مؤكد من حالة")"

echo "═══ T8: انتقال الحالة OPEN→MERGED (دورة حياة كاملة) ═══"
run_scenario
expect "رمز خروج صفري" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "لقطة البيانات قبل الدمج = open (ليست مدموجة)" "$(grep -q '"state":"open"' "$SB/backups/pr_meta_medical-ocr-trainer_77.json" && echo 0 || echo 1)"
expect "تأكيد ما بعد الدمج = merged من استجابة مختلفة" "$(python3 -I -c "import json;d=json.load(open('$SB/backups/merge_confirm_medical-ocr-trainer_77.json'));assert d['merged'] is True" 2>/dev/null && echo 0 || echo 1)"
expect "bundle موجود وغير فارغ" "$([ -s "$SB/backups/bundles/pr_medical-ocr-trainer_77.bundle" ] && echo 0 || echo 1)"
expect "manifest يحوي sha الرأس الحقيقي" "$(grep -q "$ORIGIN_SHA" "$SB/backups/backup_manifest.tsv" && echo 0 || echo 1)"
expect "استعادة مُثبتة في السجل" "$(has "استعادة مُثبتة")"
expect "MERGED بشهادة حية" "$(has "مؤكد من حالة GitHub الحية")"

echo "═══ T9: DRY_RUN=1 → لا تنفيذ ولا ادعاء MERGED حقيقي ═══"
setup_sandbox
( cd "$SB" \
    && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" DRY_RUN=1 \
    && export MOCK_STATE_FILE="$SB/state" BACKUP_REMOTE_URL="$SB/origin" \
    && source "$LIB" \
    && merge_pr "medical-ocr-trainer" 77 "feat/x" merge ) > "$SB/out.txt" 2>&1
RC=$?
LOGTXT=$(cat "$SB"/logs/*.log 2>/dev/null || true)
expect "رمز خروج صفري (محاكاة)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "الأمر لم يُنفذ" "$(has "DRY-RUN (لن يُنفذ)")"
expect "MERGED موسوم محاكاة فقط" "$(has "محاكاة DRY-RUN — بلا تنفيذ")"
expect "لا ادعاء تأكيد حي" "$(lacks "مؤكد من حالة GitHub الحية")"

echo "═══ T10: تعارض DIRTY/CONFLICTING → البوابة ترفض ═══"
run_scenario MOCK_GATE=dirty
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض التعارض صراحة" "$(has "تعارض دمج CONFLICTING")"
expect "أمر الدمج لم يُحاول" "$(lacks "gh pr merge")"

echo "═══ T11: حالة دمج BLOCKED → البوابة ترفض ═══"
run_scenario MOCK_GATE=blocked
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض الحالة غير الآمنة" "$(has "حالة الدمج غير آمنة (BLOCKED)")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T12: مراجعة CHANGES_REQUESTED → البوابة ترفض ═══"
run_scenario MOCK_GATE=changes
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض حالة المراجعة" "$(has "حالة المراجعة تمنع الدمج")"
expect "أمر الدمج لم يُحاول" "$(lacks "gh pr merge")"

echo "═══ T13: PR مغلق/مدموج مسبقًا → رفض قبل محاولة الدمج ═══"
run_scenario MOCK_GATE=closed
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض غير المفتوح" "$(has "مغلق أو مدموج مسبقًا")"
expect "أمر الدمج لم يُحاول أصلًا" "$(lacks "gh pr merge")"

echo "═══ T14: mergeable=UNKNOWN → البوابة ترفض (القيم المجهولة) ═══"
run_scenario MOCK_GATE=unknown
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض القيمة المجهولة" "$(has "قابلية الدمج غير مؤكدة")"
expect "لا MERGED" "$(lacks "MERGED")"

echo "═══ T15: حالة دمج BEHIND → البوابة ترفض ═══"
run_scenario MOCK_GATE=behind
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يرفض BEHIND" "$(has "حالة الدمج غير آمنة (BEHIND)")"
expect "أمر الدمج لم يُحاول" "$(lacks "gh pr merge")"

echo "═══ T16: فشل إنشاء bundle → لا دمج نهائيًا ═══"
run_scenario BACKUP_REMOTE_URL=/nonexistent/origin
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق فشل الـbundle" "$(has "تعذر إنشاء git bundle")"
expect "أمر الدمج لم يُحاول أصلًا" "$(lacks "gh pr merge")"

echo "═══ T17: إغلاق ناجح → CLOSED مؤكد حيًا فقط ═══"
run_close_scenario
expect "رمز خروج صفري" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "تأكيد حي في السجل" "$(has "تأكيد حي")"
expect "CLOSED مسجل بعد التأكيد" "$(has "مؤكد من حالة GitHub الحية")"

echo "═══ T18: فشل الإغلاق → لا CLOSED ═══"
run_close_scenario MOCK_CLOSE=fail
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل يوثق فشل الأمر" "$(has "فشل الأمر")"
expect "لا سطر إغلاق مؤكد" "$(lacks "CLOSED medical-ocr-trainer")"

echo "═══ T19: إغلاق في DRY_RUN → لا ادعاء CLOSED أصلًا ═══"
setup_sandbox
( cd "$SB" \
    && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" DRY_RUN=1 \
    && export MOCK_STATE_FILE="$SB/state" \
    && source "$LIB" \
    && close_pr "medical-ocr-trainer" 77 "سبب تجريبي" ) > "$SB/out.txt" 2>&1
RC=$?
LOGTXT=$(cat "$SB"/logs/*.log 2>/dev/null || true)
expect "رمز خروج صفري (محاكاة)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "الإغلاق لم يُنفذ" "$(has "DRY-RUN (لن يُنفذ): إغلاق")"
expect "لا ادعاء CLOSED" "$(lacks "CLOSED medical-ocr-trainer")"

echo
echo "═══ الخلاصة: نجح $PASS / فشل $FAIL ═══"
[ $FAIL -eq 0 ] || exit 1
