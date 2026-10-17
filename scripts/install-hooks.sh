#!/usr/bin/env bash
# يركّب خطاف pre-commit محليًا: فحص أسرار + بوابة نمط عناوين Git + الاختبارات.
# الاستخدام:  bash scripts/install-hooks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$(git -C "$REPO_ROOT" rev-parse --git-path hooks)"
HOOK="$HOOKS_DIR/pre-commit"

mkdir -p "$HOOKS_DIR"
cat > "$HOOK" <<'HOOK_BODY'
#!/usr/bin/env bash
# pre-commit: لا يُقبل commit يحمل سرًا أو عنوان Git فيه بيانات اعتماد.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
fail=0

echo "» scan_secrets (staged)"
python3 "$ROOT/scan_secrets.py" || fail=1

echo "» credential-url gate (staged)"
python3 "$ROOT/scripts/check_no_credentials_in_urls.py" --staged || fail=1

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "» pytest tests/"
  python3 -m pytest "$ROOT/tests" -q || fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "✖ pre-commit فشل — أصلح الملاحظات أو نفّذ بـ SKIP_TESTS=1 للاختبارات فقط" >&2
  exit 1
fi
echo "✔ pre-commit نظيف"
HOOK_BODY

chmod +x "$HOOK"
echo "✔ ثُبّت الخطاف في: $HOOK"
echo "  لتخطي الاختبارات عند الحاجة: SKIP_TESTS=1 git commit …"
