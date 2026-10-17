# Security Policy — repo-sync-toolkit

> repo-sync-toolkit is a **security-sensitive utility**. It handles API
> tokens, can push to remote repositories, and can rewrite history
> (force-push, with governance). Read this document before extending it.

## Threat model

The toolkit runs locally on the operator's machine. The threats it
must defend against:

1. **Accidental secret leakage** — tokens (GitHub PAT, HuggingFace
   token, Telegram api_id/api_hash) ending up in committed files,
   logs, or stdout.
2. **Accidental destructive operations** — `git push --force` to
   `main`, `git push --tags` to a sensitive training-data repo,
   `git reset --hard` losing uncommitted work.
3. **Audit gap** — operations happening with no trail, so a mistake
   cannot be traced back to its cause.

## Defense layers (current)

### 1. Secret storage

- Tokens are stored in `~/.config/git-sync-system/secrets.env` with
  `chmod 600` (owner read/write only).
- The `token-manager.py` tool masks token values by default in all
  output. Full values are shown only with the explicit `--show` flag
  on `list` / `export`.
- `secrets.env` is loaded into the environment only when running a
  sync command — it is never sourced into a shell.

### 2. .gitignore

The following paths are git-ignored (see `.gitignore`):

- `.env`, `.env.*`, `config/settings.env`, `config/secrets.*`
- `*.session`, `*.session-journal` (Telethon sessions)
- `logs/*.log`, `logs/*.log.gz`, `logs/*.jsonl` (logs may contain
  repo paths and metadata — should not be committed)

### 3. Governance layer

`governance_checker.py` enforces per-repo policies:

- An **allowlist** of repos that may receive pushes.
- A **denylist** of archived/protected repos where pushes are never
  allowed (e.g. `ai-fuel-engine` in the audit log).
- **`deny_force_push_protected=true`** — force-push to `main` is
  denied by default on protected repos.
- **Sensitive-data repos** require explicit `--force-write` and
  confirmation (e.g. `medical-ocr-ground-truth`).

Every push/force-push decision is logged to `logs/audit.log` as a
JSON line with timestamp, repo, branch, result (allowed/denied), and
a reason string.

### 4. Audit log

`logs/audit.log` is JSONL with the schema:

```json
{
  "timestamp": "2026-06-29T22:21:39.835741+00:00",
  "operation": "push" | "force-push" | "pull" | "clone" | "sync",
  "repo": "<name>",
  "branch": "<name>",
  "result": "allowed" | "denied",
  "details": "<reason>"
}
```

The audit log does NOT contain token values, file contents, or
diffs — only repo names, branches, and governance decisions.

## Hardening checklist (for contributors)

Before extending the toolkit, verify:

- [ ] No new code path prints token values without an explicit
      `--show`/`--debug` flag.
- [ ] No new code path writes secrets to `logs/` or to stdout
      without masking.
- [ ] Any new file path that may contain secrets is added to
      `.gitignore`.
- [ ] Any new destructive git operation (e.g. `git reset --hard`,
      `git clean -fd`) goes through `governance_checker.py` and is
      audit-logged.
- [ ] Any new "sync all repos" loop has a dry-run mode and a
      per-repo confirmation for destructive operations.

## Pre-commit secret scan

`scan_secrets.py` is a small standalone scanner that scans staged files
for common secret patterns (GitHub PAT `ghp_*`, HuggingFace `hf_*`,
AWS `AKIA*`, Telegram `api_hash` 32-char hex, PEM private key blocks,
and generic `token=...`/`api_key=...` assignments). On a finding it
prints the file path + line number + pattern name — NEVER the secret
value itself — and exits non-zero so a pre-commit hook can block the
commit.

Install as a pre-commit hook:

```bash
cd repo-sync-toolkit
chmod +x scan_secrets.py
ln -s ../../scan_secrets.py .git/hooks/pre-commit
```

Or run manually:

```bash
./scan_secrets.py            # scan staged files
./scan_secrets.py <file>     # scan one file
./scan_secrets.py --all      # scan all tracked files
```

## Reporting a vulnerability

If you find a way to bypass the governance layer, leak secrets via
logs, or push to a denied repo, please open a private security
advisory on GitHub rather than a public issue.

## Reference

- `ECOSYSTEM_STATE.md` — role of repo-sync-toolkit in the ecosystem.
- `GOVERNANCE.md` — high-level governance principles.
- `config/governance.yaml` — actual allowlist / denylist / policies.

---

## قاعدة إلزامية: لا بيانات اعتماد داخل عناوين Git

**ممنوع** بناء أي عنوان Git يحمل **userinfo** (أي `مستخدم:كلمة مرور` أو `مستخدم:توكن` قبل العلامة `@`)
— سواء في الشيفرة أو الأمثلة أو التوثيق. الصيغة الممنوعة هي نفسها التي تُبنى عادةً هكذا:
`https://` + `x-access` + `-token:${GITHUB_TOKEN}@github.com/owner/repo.git`.
السبب: التوكن داخل العنوان يتسرب عبر

1. `.git/config` (مخزَّن نصًّا صريحًا في كل مستودع مستنسخ)،
2. `git remote -v` وأي مخرجات تشخيص،
3. قائمة العمليات (`ps`) لأن العنوان يُمرَّر وسيطًا للأمر،
4. سجلات الأخطاء عند فشل الاستنساخ أو الدفع.

### البديل المعتمد

| البيئة | الآلية |
|---|---|
| جهاز مطوَّر | GitHub CLI: `gh auth login` ثم `gh auth setup-git` |
| Windows/macOS | Git Credential Manager |
| CI (GitHub Actions) | `GITHUB_TOKEN` المدمج عبر `actions/checkout` مع `persist-credentials`، أو SSH deploy key |
| Linux بلا واجهة | `git config --global credential.helper 'cache --timeout=3600'` أو SSH |

### الحواجز المطبَّقة (Defense in depth)

| الحاجز | الملف | السلوك |
|---|---|---|
| كشف النمط ومنع الدمج | `scripts/check_no_credentials_in_urls.py` | يرفض أي بناء عنوان يحمل userinfo مع متغير سري؛ يستثني `legacy/` (أرشيف مجمَّد) والأمثلة الموثَّقة |
| فحص الأسرار | `scan_secrets.py` | يمنع التوكنات الحقيقية، ويخفّض الأقنعة (`ghp_REPLACE_ME`، `xxx…`) إلى تحذير بدل تعطيل كل commit |
| حراسة وقت التشغيل | `config/lib-common.sh` → `url_has_credentials`, `ensure_clean_remote`, `assert_clean_url` | تفشل fail-closed قبل أي `fetch`/`push`/`clone`، وتنظّف `origin` الملوَّث دون طباعة العنوان |
| حراسة Python | `master_orchestrator.py` → `url_has_credentials`, `strip_credentials`, `assert_clean_remote`, `ensure_git_auth`, `redact` | تنفيذ بلا `shell=True` (يمنع الحقن)، وتحمير بيانات الاعتماد من كل stderr وسجل |
| الاختبارات | `tests/test_credential_hygiene.py` | 30+ اختبارًا تشمل تحكّمًا سلبيًا يعيد بناء النمط القديم ويتأكد من رفضه |
| CI | `.github/workflows/security-gate.yml` | يشغّل الحاجزَين + الاختبارات + `bash -n` + `compileall` + dry-run عند كل push/PR إلى `main` |

### ملاحظة حول التسريبات خارج المستودع

إزالة قيمة سرية من ملف **لا تُبطل التوكن**. إذا ظهر توكن في صفحة مشاركة أو محادثة
أو سجل خارج Git، فالإجراء الوحيد الحاسم هو **الإبطال من إعدادات الحساب** ثم
التحقق من رفضه، ومراجعة سجل النشاط الأمني. راجع `legacy/session-archive-2026-10-05/`
كمثال موثَّق على هذه الحالة.

### خطاف محلي اختياري

```bash
bash scripts/install-hooks.sh   # يركّب pre-commit: فحص أسرار + بوابة النمط + الاختبارات
```
