#!/usr/bin/env bash
# test_lib.sh — اختبارات سلبية/إيجابية لبوابات lib.sh بمحاكاة gh كاملة + git حقيقي
# لا شبكة، لا توكن حقيقي. غيّر البيانات عبر متغيرات MOCK_* داخل كل سيناريو.
# التغطية (جولتا مراجعة المالك الثانية والثالثة 2026-11-23):
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
#   T20 استقلال النسخة الاحتياطية عن المصدر: إزالة المستودع الأصل كليًا ثم
#       استعادة الـbundle وحده في مستودع جديد فارغ + تحقق الـsha + محتوى الملفات
#   T21 عدم تسرب التوكن: لا قيمة التوكن ولا نمط عنوانه في السجلات أو ملفات النسخ
#   T22 حرّاس التزامن: تسمية CI تطابق العدد الفعلي آليًا (آخر سيناريو عمدًا
#       كي يشمل TOTAL كل تأكيدات ما قبله)
#   T23 خادم Git HTTP محلي حقيقي يتطلب Basic Auth → git يستدعي ASKPASS فعليًا
#   T24 مراقبة متزامنة لـ/proc/*/cmdline + أثر GIT_TRACE الحاسم: التوكن غائب عن argv أثناء التنفيذ
#   T25 تنظيف askpass ومجلد العمل المؤقت بعد نجاح الجلب والتغليف
#   T26 تنظيف askpass ومجلد العمل المؤقت بعد فشل المصادقة
#   T27 عدد السيناريوهات مستخرج آليًا من العناوين الفعلية + لا تكرار ولا فجوات
#   T28 فشل المصادقة لا يسجل نجاح نسخة احتياطية ولا يواصل الدمج
#   T29 تصنيف الإصدارات الأساسي — Patch/Minor/Major + حالات الجولة الفعلية (pandas/opencv/Pillow)
#   T30 العناوين المضللة لا تحكم — Major مخفي خلف عنوان يبدو آمنًا (ci: bump / chore(deps) / actions/)
#   T31 تحديثات GitHub Actions — سياسة محافظة: Major/Minor مراجعة، Patch فقط مرشحة
#   T32 التحديثات المجمّعة — Major أو UNKNOWN واحدة تمنع تصنيفها آمنة
#   T33 غير القابل للتحليل والبيانات الناقصة → UNKNOWN بلا تخمين
#   T34 الاستثناءات الخمسة محمية — قبل أي تصنيف ولا يتجاوزها أي مسار جديد
#   T35 حارس SAFE النهائي — لا BIG ولا UNKNOWN ولا EXEMPT في قائمة الدمج الآلي
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
      && { [ "$#" -eq 0 ] || export "$@"; } \
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

# ── خادم Git HTTP محلي للمصادقة الحقيقية (جولة 4) ──
# يقدم git http-backend (بروتوكول ذكي حقيقي) خلف بوابة HTTP Basic:
# يرفض غير المصادق برمز 401 ويسجل كل طلب (المسار + هل كان مصادقًا) —
# سجل الرفض-ثم-القبول هو الدليل المباشر على استدعاء askpass من git نفسه.
# localhost فقط، منفذ يحجزه النظام آمنًا (0)، لا شبكة خارجية ولا خادم خارجي،
# وكلمة السر تمر عبر البيئة لا argv (لا قيمة سرية في وسائط أي عملية).
HTTPD_PID="" HTTP_PORT=""
start_http_server() { # $1=كلمة السر الصحيحة المتوقعة (قيمة اصطناعية لا توكن حقيقي)
  cat > "$SB/http_git_server.py" <<'PYEOF'
#!/usr/bin/env python3
import base64, os, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT, USER, LOGF, PORTF = sys.argv[1:5]
PASSWORD = os.environ["HTTP_TEST_PASS"]

def auth_ok(header):
    if not header.startswith("Basic "):
        return False
    try:
        u, _, p = base64.b64decode(header[6:].strip()).decode("utf-8", "replace").partition(":")
    except Exception:
        return False
    return u == USER and p == PASSWORD

class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, ctype, body, auth_hdr=False):
        self.send_response(code)
        if auth_hdr:
            self.send_header("WWW-Authenticate", 'Basic realm="git-local-test"')
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache, max-age=0, must-revalidate")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _handle(self):
        time.sleep(0.25)  # توسيع نافذة مراقبة argv لتناسب سرعات العدّاءات المختلفة (T24) — للاختبار فقط
        ok = auth_ok(self.headers.get("Authorization", ""))
        path, _, query = self.path.partition("?")
        with open(LOGF, "a") as f:
            f.write("%s %s auth=%s\n" % (self.command, path, "yes" if ok else "no"))
        if not ok:
            self._reply(401, "text/plain", b"credential required\n", auth_hdr=True)
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        env = dict(os.environ)
        env.update({
            "GIT_PROJECT_ROOT": ROOT, "GIT_HTTP_EXPORT_ALL": "1",
            "PATH_INFO": path, "QUERY_STRING": query,
            "REQUEST_METHOD": self.command, "REMOTE_ADDR": "127.0.0.1",
            "REMOTE_USER": USER, "CONTENT_LENGTH": str(len(body)),
            "GIT_CONFIG_NOSYSTEM": "1",
        })
        gp = self.headers.get("Git-Protocol")
        if gp:
            env["GIT_PROTOCOL"] = gp
        ct = self.headers.get("Content-Type")
        if ct:
            env["CONTENT_TYPE"] = ct
        proc = subprocess.run(["git", "http-backend"], input=body, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, env=env)
        raw = proc.stdout
        head, sep, payload = raw.partition(b"\r\n\r\n")
        if not sep:
            head, sep, payload = raw.partition(b"\n\n")
        code, ctype = 200, "application/octet-stream"
        for line in head.splitlines():
            low = line.decode("latin-1").strip().lower()
            if low.startswith("status:"):
                try:
                    code = int(low.split(":", 1)[1].strip().split()[0])
                except Exception:
                    code = 200
            elif low.startswith("content-type:"):
                ctype = line.decode("latin-1").split(":", 1)[1].strip()
        self._reply(code, ctype, payload)

    do_GET = _handle
    do_POST = _handle

    def log_message(self, *args):  # صمت سجلات stderr القياسية
        pass

srv = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORTF, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF
  HTTP_TEST_PASS="$1" python3 -I "$SB/http_git_server.py" "$SB" "x-access-token" \
    "$SB/http_server.log" "$SB/http_port" &
  HTTPD_PID=$!
  local i
  for i in $(seq 1 50); do [ -s "$SB/http_port" ] && break; sleep 0.1; done
  HTTP_PORT=$(cat "$SB/http_port" 2>/dev/null || true)
}
stop_http_server() {
  if [ -n "${HTTPD_PID:-}" ]; then
    kill "$HTTPD_PID" 2>/dev/null
    wait "$HTTPD_PID" 2>/dev/null
  fi
  HTTPD_PID=""   # HTTP_PORT يبقى للتحقق اللاحق؛ يُستبدل عند بدء الخادم التالي
}
# يشغّل merge_pr عبر خادم Git HTTP محلي حقيقي (جولة 4)؛
# $1=كلمة سر الخادم الصحيحة (الخطأ عمدًا في سيناريوهات فشل المصادقة)،
# والبقية تصديرات إضافية للسيناريو. GIT_CONFIG_* تعزل العميل عن أي
# credential helper أو إعدادات على الجهاز — askpass هو المصدر الوحيد.
run_http_scenario() {
  local correct_pass="$1"; shift
  setup_sandbox
  start_http_server "$correct_pass"
  ( cd "$SB" \
      && export PATH="$MOCKDIR:$PATH" GH_TOKEN="dummy-token-for-mock-only" \
      && export DRY_RUN=0 MOCK_STATE_FILE="$SB/state" \
      && export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
      && export BACKUP_REMOTE_URL="http://127.0.0.1:${HTTP_PORT}/origin" \
      && { [ "$#" -eq 0 ] || export "$@"; } \
      && source "$LIB" \
      && merge_pr "medical-ocr-trainer" 77 "feat/x" merge ) > "$SB/out.txt" 2>&1
  RC=$?
  stop_http_server
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

echo "═══ T20: استقلال النسخة الاحتياطية — استعادة الـbundle بعد إزالة المصدر كليًا ═══"
run_scenario
expect "بناء نسخة سليمة أولًا (رمز خروج صفري)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
rm -rf "$SB/origin"   # قطع الوصول للمصدر نهائيًا: لا مستودع أصل، ولا شبكة
R2="$(mktemp -d /tmp/librestore.XXXXXX)"
git clone -q "$SB/backups/bundles/pr_medical-ocr-trainer_77.bundle" "$R2" 2>/dev/null
expect "الاستنساخ من الـbundle وحده ناجح (بلا مصدر وبلا شبكة)" "$([ -d "$R2/.git" ] && echo 0 || echo 1)"
expect "الـcommit المستعاد موجود بالـsha الأصلي نفسه" "$(git -C "$R2" cat-file -e "$ORIGIN_SHA^{commit}" 2>/dev/null && echo 0 || echo 1)"
expect "محتوى ملفات الـcommit المستعاد مطابق" "$([ "$(git -C "$R2" show "$ORIGIN_SHA":file.txt 2>/dev/null)" = "source" ] && echo 0 || echo 1)"
rm -rf "$R2"

echo "═══ T21: عدم تسرب التوكن في السجلات وملفات النسخ ═══"
run_scenario
expect "تشغيل كامل أنتج السجلات والنسخ (رمز خروج صفري)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
LEAKS=$(grep -r -l "dummy-token-for-mock-only" "$SB/logs" "$SB/backups" 2>/dev/null | wc -l)
expect "لا قيمة التوكن في أي ملف أنتجه التشغيل (سجلات/لقطات/manifest/bundle)" "$([ "$LEAKS" -eq 0 ] && echo 0 || echo 1)"
LEAKS2=$(grep -r -l "x-access-token" "$SB/logs" "$SB/backups" 2>/dev/null | wc -l)
expect "لا نمط توكن-في-العنوان في المخرجات (سكربت المصادقة حُذف مع المستودع المؤقت)" "$([ "$LEAKS2" -eq 0 ] && echo 0 || echo 1)"
expect "lib.sh بلا توكن داخل أي عنوان Git" "$(grep -q "https://x-access-token:" "$LIB" && echo 1 || echo 0)"

echo "═══ T23: خادم Git HTTP محلي حقيقي يتطلب Basic Auth ويستدعي ASKPASS فعليًا ═══"
run_http_scenario "dummy-token-for-mock-only"
expect "الخادم جاهز على منفذ يحجزه النظام آمنًا (localhost فقط)" "$([ -n "$HTTP_PORT" ] && echo 0 || echo 1)"
expect "رمز خروج صفري (المسار الكامل نجح عبر HTTP مصادق)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "دليل استدعاء askpass حي: الرفض (auth=no) ثم القبول (auth=yes) — والعميلة بلا مصدر آخر (لا طرفية GIT_TERMINAL_PROMPT=0 ولا credential helper معزول)" "$([ "$(grep -c "auth=no" "$SB/http_server.log" 2>/dev/null)" -ge 1 ] && [ "$(grep -c "auth=yes" "$SB/http_server.log" 2>/dev/null)" -ge 1 ] && echo 0 || echo 1)"
expect "bundle موجود وغير فارغ عبر مسار HTTP" "$([ -s "$SB/backups/bundles/pr_medical-ocr-trainer_77.bundle" ] && echo 0 || echo 1)"
expect "manifest يحوي sha الرأس الحقيقي (نجاح التغليف عبر HTTP)" "$(grep -q "$ORIGIN_SHA" "$SB/backups/backup_manifest.tsv" 2>/dev/null && echo 0 || echo 1)"
expect "العنوان خالٍ من التوكن: لا قيمة اصطناعية في سجل الخادم أو سجلات التشغيل" "$([ "$(grep -l "dummy-token-for-mock-only" "$SB/http_server.log" "$SB/out.txt" "$LOG" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"
expect "لا نمط بيانات-اعتماد-داخل-عنوان (user:pass@) في سجل الخادم أو السجلات" "$([ "$(grep -l "x-access-token:" "$SB/http_server.log" "$SB/out.txt" "$LOG" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"

echo "═══ T24: التوكن غائب عن argv لعمليات Git أثناء التنفيذ (مراقبة /proc متزامنة) ═══"
ARGVDUMP="$(mktemp /tmp/libargvdump.XXXXXX)"
ARGVOBS="$(mktemp /tmp/libargvobs.XXXXXX)"
STOPF="$(mktemp /tmp/libargvstop.XXXXXX)"
WPY="$(mktemp /tmp/libwatcher.XXXXXX)"
cat > "$WPY" <<'PYEOF'
#!/usr/bin/env python3
# مراقب /proc المتزامن — قراءة سريعة بلا fork لكل عملية، وبحد زمني صارم من
# الداخل (40ث) ومن الخارج (timeout 45) كي لا يعلق انتظار المراقب أبدًا؛
# نسخة bash (فورك/قراءة لكل pid) علقت في بيئة الاختبار فعليًا وعولجت هنا.
import os, sys, time

DUMP, OBS, STOPF = sys.argv[1:4]
deadline = time.time() + 40.0
while time.time() < deadline:
    try:
        if os.path.getsize(STOPF) > 0:
            break
    except OSError:
        pass
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                raw = f.read()
        except OSError:
            continue
        if not raw:
            continue
        cl = raw.replace(b"\x00", b" ").decode("utf-8", "replace")
        if "git" in cl and ("fetch" in cl or "git -C" in cl):
            with open(DUMP, "a") as f:
                f.write(cl + "\n")
        if "refs/heads/backup" in cl:
            with open(OBS, "a") as f:
                f.write(cl + "\n")
    time.sleep(0.005)
PYEOF
timeout 45 python3 -I "$WPY" "$ARGVDUMP" "$ARGVOBS" "$STOPF" &
WATCHER=$!
# GIT_TRACE=1: أثر argv حاسم عند لحظة التنفيذ لكل عملية git — لا يعتمد على العينات
run_http_scenario "dummy-token-for-mock-only" GIT_TRACE=1
printf 'stop\n' > "$STOPF"
wait "$WATCHER" 2>/dev/null
expect "المراقب التقاط عملية git fetch حية أثناء التنفيذ (إثبات صحة ملاحظة /proc)" "$([ -s "$ARGVOBS" ] && echo 0 || echo 1)"
expect "أثر argv حاسم من git نفسه: GIT_TRACE سجل أمر الجلب بلا عينات ولا سباق" "$(grep -q "trace: built-in: git.*fetch" "$SB/out.txt" 2>/dev/null && echo 0 || echo 1)"
expect "لا قيمة التوكن في أي argv ملتقط من /proc" "$(grep -q "dummy-token-for-mock-only" "$ARGVDUMP" 2>/dev/null && echo 1 || echo 0)"
expect "لا قيمة التوكن في أثر argv الكامل (GIT_TRACE)" "$(grep -q "dummy-token-for-mock-only" "$SB/out.txt" 2>/dev/null && echo 1 || echo 0)"
expect "لا نمط user:pass@ في ملاحظة /proc ولا في أثر GIT_TRACE" "$([ "$(grep -l "x-access-token:" "$ARGVDUMP" "$SB/out.txt" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"
expect "السيناريو المصادق نجح كاملًا أثناء المراقبة (رمز خروج صفري)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
rm -f "$ARGVDUMP" "$ARGVOBS" "$STOPF" "$WPY"

echo "═══ T25: تنظيف askpass والمستودع المؤقت بعد نجاح الجلب والتغليف ═══"
run_http_scenario "dummy-token-for-mock-only"
expect "رمز خروج صفري (نجاح)" "$([ $RC -eq 0 ] && echo 0 || echo 1)"
expect "الـbundle أُنشئ فعلًا" "$([ -s "$SB/backups/bundles/pr_medical-ocr-trainer_77.bundle" ] && echo 0 || echo 1)"
expect "لا أثر لسكربت askpass بعد النجاح" "$([ "$(find "$SB" -name ".askpass" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"
expect "لا مجلدات عمل مؤقتة متبقية (.bk_scratch/.bk_restore/.bk_verify)" "$([ "$(find "$SB" -maxdepth 1 -name ".bk_*" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"

echo "═══ T26: تنظيف askpass والمستودع المؤقت بعد فشل المصادقة ═══"
run_http_scenario "wrong-password-on-purpose"
expect "رمز خروج غير صفري (backup_pr فشل)" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "الخادم وثّق رفض المصادقة فعليًا (طلبات auth=no)" "$(grep -q "auth=no" "$SB/http_server.log" 2>/dev/null && echo 0 || echo 1)"
expect "لا أثر لسكربت askpass بعد الفشل" "$([ "$(find "$SB" -name ".askpass" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"
expect "لا مجلدات عمل مؤقتة متبقية بعد الفشل" "$([ "$(find "$SB" -maxdepth 1 -name ".bk_*" 2>/dev/null | wc -l)" -eq 0 ] && echo 0 || echo 1)"
expect "لا bundle أُنشئ عند فشل المصادقة" "$([ ! -e "$SB/backups/bundles/pr_medical-ocr-trainer_77.bundle" ] && echo 0 || echo 1)"

echo "═══ T28: فشل المصادقة لا يسجل نجاح نسخة احتياطية ولا يواصل الدمج ═══"
run_http_scenario "wrong-password-on-purpose"
expect "رمز خروج غير صفري" "$([ $RC -ne 0 ] && echo 0 || echo 1)"
expect "السجل لا يعلن نسخة احتياطية مؤكدة" "$(lacks "نسخة احتياطية مستقلة مؤكدة")"
expect "لا manifest نسخ احتياطية أصلًا (النسخة لم تكتمل)" "$([ ! -e "$SB/backups/backup_manifest.tsv" ] && echo 0 || echo 1)"
expect "أمر الدمج لم يُحاول أصلًا (fail-closed)" "$(lacks "gh pr merge")"
expect "لا MERGED" "$(lacks "MERGED")"

# ── تصنيف Dependabot (جولة إصلاح 5): استدعاء مباشر لـdep_classify من 30_dependabot.sh ──
# بلا gh وبلا شبكة: ملف JSONL ثابت ← تصنيف ← فحص الفئات والأهلية. القرار من
# بيانات الإصدار القديم/الجديد في جسم الـPR — لا من العنوان.
DEP30="$HERE/../30_dependabot.sh"
FIX="$(mktemp /tmp/depfix.XXXXXX)"
CLASSOUT="$(mktemp /tmp/depout.XXXXXX)"
dep_row() { # يطبع سطر JSONL: repo n head title body
  python3 -I - "$@" <<'PYEOF'
import json, sys
repo, n, head, title, body = sys.argv[1:6]
print(json.dumps({"repo": repo, "n": int(n), "head": head, "title": title,
                  "body": body}, ensure_ascii=False))
PYEOF
}
add_row() { dep_row "$@" >> "$FIX"; }
run_classify() { # $1+=تصديرات إضافية للسيناريو (مثل DEP_POLICY_ALLOW_MINOR=1)
  : > "$CLASSOUT"
  ( { [ "$#" -eq 0 ] || export "$@"; }
    source "$DEP30"
    dep_classify "$FIX" ) > "$CLASSOUT" 2>&1
}
cat_of() { # repo n → الفئة
  python3 -I - "$1" "$2" "$CLASSOUT" <<'PYEOF'
import json, sys
repo, n, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
for line in open(path):
    d = json.loads(line)
    if d["repo"] == repo and d["n"] == n:
        print(d["category"]); break
PYEOF
}
elig_of() { # repo n → 0 إن كان آليًا (eligible) وإلا 1
  python3 -I - "$1" "$2" "$CLASSOUT" <<'PYEOF'
import json, sys
repo, n, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
for line in open(path):
    d = json.loads(line)
    if d["repo"] == repo and d["n"] == n:
        print("0" if d["eligible"] else "1"); break
PYEOF
}
n_elig() { # عدد الصفوف الآلية في آخر تصنيف
  python3 -I -c "import json;print(sum(1 for l in open('$CLASSOUT') if json.loads(l).get('eligible')))"
}

echo "═══ T29: تصنيف الإصدارات الأساسي — Patch/Minor/Major + حالات الجولة الفعلية (pandas/opencv/Pillow) ═══"
: > "$FIX"
add_row "repo-a" 1 "" "Bump lib from 1.2.3 to 1.2.4" $'Bumps [lib](https://ex.test/a) from 1.2.3 to 1.2.4.'
add_row "repo-a" 2 "" "Bump lib from 1.2.3 to 1.3.0" $'Bumps [lib](https://ex.test/a) from 1.2.3 to 1.3.0.'
add_row "repo-a" 3 "" "Bump lib from 1.2.3 to 2.0.0" $'Bumps [lib](https://ex.test/a) from 1.2.3 to 2.0.0.'
add_row "medical-ocr-ground-truth" 15 "dependabot/pip/pandas-gte-3.1.1" "chore(deps): update pandas requirement from >=2.0.0 to >=3.1.1" $'Updates `pandas` requirement from >=2.0.0 to >=3.1.1\n\n- [Changelog](https://pandas.pydata.org/docs/whatsnew/v3.1.1.html)'
add_row "medical-ocr-demo" 6 "dependabot/pip/opencv-python-headless-gte-5.1.0.95" "chore(deps): update opencv-python-headless requirement from >=4.8.0 to >=5.1.0.95" $'Updates `opencv-python-headless` requirement from >=4.8.0 to >=5.1.0.95'
add_row "medical-ocr-demo" 5 "dependabot/pip/pillow-gte-13.0.0" "chore(deps): update pillow requirement from >=10.0.0 to >=13.0.0" $'Updates `pillow` requirement from >=10.0.0 to >=13.0.0'
run_classify
expect "Patch 1.2.3→1.2.4 مصنف PATCH" "$([ "$(cat_of repo-a 1)" = "PATCH" ] && echo 0 || echo 1)"
expect "Patch مرشح للدمج الآلي" "$(elig_of repo-a 1)"
expect "Minor 1.2.3→1.3.0 مصنف MINOR" "$([ "$(cat_of repo-a 2)" = "MINOR" ] && echo 0 || echo 1)"
expect "Minor خارج السياسة الافتراضية — ليس آليًا" "$([ "$(elig_of repo-a 2)" = "1" ] && echo 0 || echo 1)"
expect "Major 1.2.3→2.0.0 مصنف BIG" "$([ "$(cat_of repo-a 3)" = "BIG" ] && echo 0 || echo 1)"
expect "Major ليس آليًا" "$([ "$(elig_of repo-a 3)" = "1" ] && echo 0 || echo 1)"
expect "pandas >=2.0.0→>=3.1.1 (حالة الجولة الفعلية) = BIG رغم عنوان chore(deps)" "$([ "$(cat_of medical-ocr-ground-truth 15)" = "BIG" ] && echo 0 || echo 1)"
expect "opencv >=4.8.0→>=5.1.0.95 = BIG" "$([ "$(cat_of medical-ocr-demo 6)" = "BIG" ] && echo 0 || echo 1)"
expect "Pillow >=10.0.0→>=13.0.0 = BIG" "$([ "$(cat_of medical-ocr-demo 5)" = "BIG" ] && echo 0 || echo 1)"
expect "الآلي الوحيد في المجموعة هو الـPatch (العدد=1)" "$([ "$(n_elig)" = "1" ] && echo 0 || echo 1)"

echo "═══ T30: العناوين المضللة لا تحكم — Major مخفي خلف عنوان يبدو آمنًا ═══"
: > "$FIX"
add_row "repo-b" 7 "" "ci: bump tooling" $'Bumps [pkg](https://ex.test/b) from 1.0.0 to 2.0.0.'
add_row "repo-b" 8 "" "chore(deps): bump pillow" $'Updates `pillow` requirement from >=10.0.0 to >=13.0.0'
add_row "repo-b" 9 "" "Bump actions/cache from 1.0.0 to 2.0.0" $'Bumps [pytest](https://ex.test/c) from 1.2.3 to 2.0.0.'
run_classify
expect "عنوان ci: bump يخفي Major في الجسم → BIG" "$([ "$(cat_of repo-b 7)" = "BIG" ] && echo 0 || echo 1)"
expect "عنوان chore(deps) مضلل مع Major في الجسم → BIG" "$([ "$(cat_of repo-b 8)" = "BIG" ] && echo 0 || echo 1)"
expect "عنوان يذكر actions/ لكن الجسم ترقية Python Major → BIG (العنوان لا يصنّف)" "$([ "$(cat_of repo-b 9)" = "BIG" ] && echo 0 || echo 1)"
expect "لا واحد من الثلاثة آلي (العدد=0)" "$([ "$(n_elig)" = "0" ] && echo 0 || echo 1)"

echo "═══ T31: تحديثات GitHub Actions — سياسة محافظة تقرأ الإصدار لا العنوان ═══"
: > "$FIX"
add_row "repo-c" 10 "dependabot/github_actions/actions/checkout-5.0.0" "Bump actions/checkout from 4 to 5" $'Bumps [actions/checkout](https://ex.test/co) from 4 to 5.'
add_row "repo-c" 11 "dependabot/github_actions/actions/cache-4.1.3" "Bump actions/cache from 4.1.2 to 4.1.3" $'Bumps [actions/cache](https://ex.test/ca) from 4.1.2 to 4.1.3.'
add_row "repo-c" 12 "dependabot/github_actions/actions/cache-4.2.0" "Bump actions/cache from 4.1.0 to 4.2.0" $'Bumps [actions/cache](https://ex.test/ca) from 4.1.0 to 4.2.0.'
add_row "repo-c" 13 "dependabot/pip/lib-gte-1.3.0" "chore(deps): bump lib" $'Updates `lib` requirement from >=1.2.0 to >=1.3.0'
run_classify
expect "actions Major (4→5) = BIG — احتواء العنوان على actions/ لا يصنّف آمنًا" "$([ "$(cat_of repo-c 10)" = "BIG" ] && echo 0 || echo 1)"
expect "actions Patch (4.1.2→4.1.3) = PATCH مرشحة" "$([ "$(cat_of repo-c 11)" = "PATCH" ] && echo 0 || echo 1)"
expect "actions Minor (4.1.0→4.2.0) = BIG سياسة محافظة" "$([ "$(cat_of repo-c 12)" = "BIG" ] && echo 0 || echo 1)"
run_classify DEP_POLICY_ALLOW_MINOR=1
expect "تفعيل السياسة لا يفتح actions minor — تبقى BIG (محافظة)" "$([ "$(cat_of repo-c 12)" = "BIG" ] && echo 0 || echo 1)"
expect "تفعيل السياسة يفتح minor العادي فقط (eligible)" "$(elig_of repo-c 13)"

echo "═══ T32: التحديثات المجمّعة — Major أو UNKNOWN واحدة تمنع تصنيفها آمنة ═══"
: > "$FIX"
add_row "repo-d" 20 "dependabot/pip/group-a" "Bump group a" $'Bumps [a](https://ex.test/x) from 1.0.0 to 1.0.1.\n\n---\n\nBumps [b](https://ex.test/y) from 1.0.0 to 2.0.0.'
add_row "repo-d" 21 "dependabot/pip/group-b" "Bump group b" $'Bumps [a](https://ex.test/x) from 1.0.0 to 1.0.1.\n\n---\n\nBumps [b](https://ex.test/y) from 2.0.0 to 2.0.1.'
add_row "repo-d" 22 "dependabot/pip/group-c" "Bump group c" $'Bumps [a](https://ex.test/x) from 1.0.0 to 1.0.1.\n\n---\n\nBumps [b](https://ex.test/y) from 1.0.0 to 1.0.nan'
run_classify
expect "مجمّعة فيها Major واحدة → BIG (المجموعة كلها غير آمنة)" "$([ "$(cat_of repo-d 20)" = "BIG" ] && echo 0 || echo 1)"
expect "مجمّعة Patch كاملة → PATCH مرشحة" "$([ "$(cat_of repo-d 21)" = "PATCH" ] && echo 0 || echo 1)"
expect "مجمّعة فيها إصدار غير قابل للتحليل → UNKNOWN" "$([ "$(cat_of repo-d 22)" = "UNKNOWN" ] && echo 0 || echo 1)"
expect "المجمّعة غير القابلة للتحليل ليست آلية" "$([ "$(elig_of repo-d 22)" = "1" ] && echo 0 || echo 1)"

echo "═══ T33: غير القابل للتحليل والبيانات الناقصة → UNKNOWN بلا تخمين ═══"
: > "$FIX"
add_row "repo-e" 30 "" "Bump x" $'Updates `x` requirement from >=1.2.3 to >=latest'
add_row "repo-e" 31 "" "Update requirements" $'Updates requirements\n\n- [Changelog](https://ex.test/ch)\n\nNo version data here.'
add_row "repo-e" 32 "" "Bump x from 1.2.3 to 1.2.3" $'Bumps [x](https://ex.test/x) from 1.2.3 to 1.2.3.'
add_row "repo-e" 33 "" "Bump x" $'Updates `x` requirement from >=1.2.3.post1 to >=1.2.4'
add_row "repo-e" 34 "" "Bump x" $'Bumps [x](https://ex.test/x) from v1.2.3 to v1.2.4.'
run_classify
expect "إصدار جديد غير قابل للتحليل (latest) → UNKNOWN" "$([ "$(cat_of repo-e 30)" = "UNKNOWN" ] && echo 0 || echo 1)"
expect "غياب بيانات الإصدار القديم والجديد → UNKNOWN" "$([ "$(cat_of repo-e 31)" = "UNKNOWN" ] && echo 0 || echo 1)"
expect "إصداران متساويان (لا ترقية مثبتة) → UNKNOWN" "$([ "$(cat_of repo-e 32)" = "UNKNOWN" ] && echo 0 || echo 1)"
expect "صيغة لا تطابق semver حرفيًا (post1) → UNKNOWN بلا تخمين" "$([ "$(cat_of repo-e 33)" = "UNKNOWN" ] && echo 0 || echo 1)"
expect "v-prefix شائع يُحلل صحيحًا (v1.2.3→v1.2.4 = PATCH)" "$([ "$(cat_of repo-e 34)" = "PATCH" ] && echo 0 || echo 1)"
expect "الآلي الوحيد هو حالة الـv-prefix (العدد=1)" "$([ "$(n_elig)" = "1" ] && echo 0 || echo 1)"

echo "═══ T34: الاستثناءات الخمسة محمية — قبل أي تصنيف ولا يتجاوزها أي مسار جديد ═══"
: > "$FIX"
add_row "marathon_ted_pipeline" 32 "" "Bump x" $'Bumps [x](https://ex.test/x) from 1.0.0 to 2.0.0.'
add_row "omni-medical-suite" 84 "" "Bump x" $'Bumps [x](https://ex.test/x) from 4.8.0 to 4.8.1.'
add_row "medical-ocr-trainer-hf" 9 "" "chore(deps): bump x" $'Updates `x` requirement from >=1.0.0 to >=1.1.0'
add_row "marathon_ted_pipeline" 33 "" "Bump y" $'Bumps [y](https://ex.test/x) from 1.2.3 to 1.2.4.'
run_classify
expect "استثناء marathon_ted_pipeline:32 (جسمه Major) = EXEMPT وليس آليًا" "$([ "$(cat_of marathon_ted_pipeline 32)" = "EXEMPT" ] && echo 0 || echo 1)"
expect "استثناء omni-medical-suite:84 — حتى بجسم Patch يبقى EXEMPT" "$([ "$(cat_of omni-medical-suite 84)" = "EXEMPT" ] && echo 0 || echo 1)"
expect "استثناء medical-ocr-trainer-hf:9 (جسمه Minor) = EXEMPT" "$([ "$(cat_of medical-ocr-trainer-hf 9)" = "EXEMPT" ] && echo 0 || echo 1)"
expect "المطابقة repo:رقم دقيقة — marathon_ted_pipeline:33 غير المستثنى يصنف PATCH" "$([ "$(cat_of marathon_ted_pipeline 33)" = "PATCH" ] && echo 0 || echo 1)"
run_classify DEP_POLICY_ALLOW_MINOR=1
expect "تفعيل السياسة لا يتجاوز الاستثناءات (9 يبقى EXEMPT)" "$([ "$(cat_of medical-ocr-trainer-hf 9)" = "EXEMPT" ] && echo 0 || echo 1)"
expect "والاستثناء ليس آليًا حتى مع السياسة المفعلة" "$([ "$(elig_of medical-ocr-trainer-hf 9)" = "1" ] && echo 0 || echo 1)"

echo "═══ T35: حارس SAFE النهائي — لا BIG ولا UNKNOWN ولا EXEMPT في قائمة الدمج الآلي ═══"
: > "$FIX"
add_row "g1" 1 "" "safe patch" $'Bumps [x](https://ex.test/x) from 1.2.3 to 1.2.4.'
add_row "g1" 2 "" "major" $'Bumps [x](https://ex.test/x) from 1.0.0 to 2.0.0.'
add_row "g1" 3 "" "unknown" $'Updates `x` requirement from >=1.2.3 to >=latest'
add_row "marathon_ted_pipeline" 32 "" "exempt patch" $'Bumps [x](https://ex.test/x) from 1.2.3 to 1.2.4.'
add_row "g1" 4 "" "minor" $'Bumps [x](https://ex.test/x) from 1.2.0 to 1.3.0.'
run_classify
SAFELIST="$(mktemp /tmp/depsafe.XXXXXX)"
( source "$DEP30"; dep_safe_extract "$CLASSOUT" ) > "$SAFELIST"
expect "قائمة الدمج الآلي تحوي المرشح الآمن الوحيد فقط (العدد=1)" "$([ "$(python3 -I -c "import json;print(len(json.load(open('$SAFELIST'))))")" = "1" ] && echo 0 || echo 1)"
expect "المرشح الآلي هو g1#1 (patch) بالضبط" "$(python3 -I -c "import json;d=json.load(open('$SAFELIST'));print(0 if d==[['g1',1,'','safe patch']] else 1)")"
expect "صفر صفوف eligible بفئة خارج PATCH/MINOR في كل المخرجات" "$(python3 -I - "$CLASSOUT" <<'PYEOF'
import json, sys
bad = sum(1 for line in open(sys.argv[1]) if line.strip()
          and json.loads(line).get("eligible")
          and json.loads(line)["category"] not in ("PATCH", "MINOR"))
print(0 if bad == 0 else 1)
PYEOF
)"
expect "صفر BIG/UNKNOWN/EXEMPT وصلوا لقائمة الدمج الآلي" "$(python3 -I - "$SAFELIST" "$CLASSOUT" <<'PYEOF'
import json, sys
keys = {(r[0], r[1]) for r in json.load(open(sys.argv[1]))}
bad = sum(1 for line in open(sys.argv[2]) if line.strip()
          and json.loads(line)["category"] in ("BIG", "UNKNOWN", "EXEMPT")
          and (json.loads(line)["repo"], json.loads(line)["n"]) in keys)
print(0 if bad == 0 else 1)
PYEOF
)"
rm -f "$SAFELIST"
rm -f "$FIX" "$CLASSOUT"

echo "═══ T27: عدد السيناريوهات مستخرج آليًا من العناوين الفعلية + تسلسل سليم ═══"
# لا اعتماد على تعليق التغطية: الاستخراج من أسطر echo "═══ T<n>:" في جسم الاختبارات نفسه
SCENS=$(grep -oE '^echo "═══ T[0-9]+:' "$HERE/test_lib.sh" | grep -oE '[0-9]+' | sort -n)
SCEN_N=$(printf '%s\n' "$SCENS" | wc -l)
DUPS=$(printf '%s\n' "$SCENS" | uniq -d | wc -l)
GAP=""
for i in $(seq 1 "$SCEN_N"); do printf '%s\n' "$SCENS" | grep -qx "$i" || GAP="$i"; done
expect "لا تكرار في أرقام السيناريوهات" "$([ "$DUPS" -eq 0 ] && echo 0 || echo 1)"
expect "التسلسل متصل بلا فجوات من T1 حتى آخر سيناريو" "$([ -z "$GAP" ] && echo 0 || echo 1)"
WF="$HERE/../../../.github/workflows/phase1_scripts_ci.yml"
if [ -f "$WF" ]; then
  expect "وصف CI يطابق العدد المستخرج آليًا من عناوين الاختبارات ($SCEN_N سيناريو)" "$(grep -q "عبر $SCEN_N سيناريو" "$WF" && echo 0 || echo 1)"
else
  expect "ملف CI غير موجود من هذا المسار — تخطٍّ (الحارس يعمل في مستودع مكتمل)" "0"
fi

echo "═══ T22: تسمية CI تطابق الأعداد الفعلية آليًا (حارس تزامن — آخر سيناريو عمدًا) ═══"
# تُنفَّذ أخيرًا كي يشمل TOTAL كل تأكيدات السيناريوهات السابقة؛ إن تغيّر أي عدد
# (تأكيدات أو سيناريوهات) فشل هذا الاختبار وجبر تحديث تسمية CI في نفس الدفعة.
WF="$HERE/../../../.github/workflows/phase1_scripts_ci.yml"
TOTAL=$((PASS + FAIL + 2))   # +2: تأكيدا هذا الاختبار نفسه (آخر سيناريو)
SCEN2=$(grep -oE '^echo "═══ T[0-9]+:' "$HERE/test_lib.sh" | grep -oE '[0-9]+' | wc -l)
if [ -f "$WF" ]; then
  expect "الوصف يتضمن العدد الكلي الفعلي للتأكيدات ($TOTAL تأكيدًا)" "$(grep -q "— $TOTAL تأكيدًا" "$WF" && echo 0 || echo 1)"
  expect "الوصف يتضمن عدد السيناريوهات المستخرج آليًا ($SCEN2 سيناريو)" "$(grep -q "عبر $SCEN2 سيناريو" "$WF" && echo 0 || echo 1)"
else
  expect "ملف CI غير موجود من هذا المسار — تخطٍّ عدد التأكيدات (الحارس يعمل في مستودع مكتمل)" "0"
  expect "ملف CI غير موجود من هذا المسار — تخطٍّ عدد السيناريوهات (الحارس يعمل في مستودع مكتمل)" "0"
fi

echo
echo "═══ الخلاصة: نجح $PASS / فشل $FAIL ═══"
[ $FAIL -eq 0 ] || exit 1
