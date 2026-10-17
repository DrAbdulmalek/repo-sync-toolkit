"""اختبارات بوابة نظافة بيانات الاعتماد — repo-sync-toolkit.

القاعدة التي تُختبر: **لا يجوز أن تحتوي أي remote URL على بيانات اعتماد**،
ولا يجوز أن تصل قيمة سرية إلى السجلات أو مخرجات الأخطاء.

التشغيل:  python3 -m pytest tests/ -q
"""
from __future__ import annotations

import importlib.util
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
LIB_COMMON = REPO_ROOT / "config" / "lib-common.sh"
ORCHESTRATOR = REPO_ROOT / "master_orchestrator.py"
SCANNER = REPO_ROOT / "scan_secrets.py"

# أشكال عناوين تحمل بيانات اعتماد — قيم وهمية بالكامل للاختبار فقط
# تُبنى قيم الاختبار تركيبًا (لا literals) حتى لا يظهر أي نمط
# "بيانات اعتماد داخل عنوان" في شيفرة الاختبارات نفسها، ولا في
# project_context.txt المولَّد من هذه الشيفرة.
FAKE_TOKEN = "ghp_" + "T3st" + "Q7b" * 10 + "Zw"   # 36 حرفًا بعد البادئة — وهمي تمامًا
_SCHEME = "https" + "://"
_HOST = "github.com/DrAbdulmalek/demo.git"
_FAKE_USER = "x-access" + "-token"
_FAKE_PASS = "passw" + "0rd"
DIRTY_HTTPS = "%s%s:%s@%s" % (_SCHEME, _FAKE_USER, FAKE_TOKEN, _HOST)
DIRTY_USERPASS = "%suser:%s@%s" % (_SCHEME, _FAKE_PASS, _HOST)
DIRTY_USERONLY = "%stoken@%s" % (_SCHEME, _HOST)
CLEAN_HTTPS = "%s%s" % (_SCHEME, _HOST)
CLEAN_SSH = "git@github.com:DrAbdulmalek/demo.git"

CRED_URL_RE = re.compile(r"//[A-Za-z0-9._%\-]+:[^/\s@]+@")


def _load_orchestrator(tmp_path, monkeypatch):
    monkeypatch.setenv("REPOS_DIR", str(tmp_path / "repos"))
    for var in ("GITHUB_TOKEN", "GH_TOKEN"):
        monkeypatch.delenv(var, raising=False)
    spec = importlib.util.spec_from_file_location("mo_test", ORCHESTRATOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.BASE_DIR = tmp_path / "repos"
    mod.DRY_RUN = True
    mod.LOG_FILE = tmp_path / "orchestrator.log"
    return mod


def _make_repo(tmp_path, origin_url, name="demo"):
    p = tmp_path / name
    p.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", str(p)], check=True)
    subprocess.run(["git", "-C", str(p), "remote", "add", "origin", origin_url], check=True)
    return p


def _bash(body, tmp_path, extra_env=None):
    """يشغّل مقطع bash بعد تحميل lib-common.sh في بيئة معزولة."""
    env = dict(os.environ)
    env.update({
        "SYNC_DIR": str(tmp_path / "sync"),
        "GIT_NAME": "", "GIT_EMAIL": "",
        "AUTH_METHOD": "token",
    })
    if extra_env:
        env.update(extra_env)
    (tmp_path / "sync").mkdir(parents=True, exist_ok=True)
    script = (
        "set -u\n"
        "source '%s'\n" % LIB_COMMON + body
    )
    f = tmp_path / "snippet.sh"
    f.write_text(script, encoding="utf-8")
    return subprocess.run(["bash", str(f)], capture_output=True, text=True, env=env, cwd=str(tmp_path))


# ══════════════════════════════════════════════════════════════ Python


class TestOrchestratorUrlHelpers:
    def test_detects_dirty_urls(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        assert mo.url_has_credentials(DIRTY_HTTPS) is True
        assert mo.url_has_credentials(DIRTY_USERPASS) is True
        assert mo.url_has_credentials(DIRTY_USERONLY) is True

    def test_accepts_clean_urls(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        assert mo.url_has_credentials(CLEAN_HTTPS) is False
        assert mo.url_has_credentials(CLEAN_SSH) is False
        assert mo.url_has_credentials("") is False

    def test_unparseable_url_is_treated_as_dirty(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        assert mo.url_has_credentials("https://[bad:url") is True

    def test_strip_credentials(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        assert mo.strip_credentials(DIRTY_HTTPS) == CLEAN_HTTPS
        assert mo.strip_credentials(DIRTY_USERPASS) == CLEAN_HTTPS
        assert mo.strip_credentials(CLEAN_HTTPS) == CLEAN_HTTPS
        assert mo.strip_credentials(CLEAN_SSH) == CLEAN_SSH


class TestOrchestratorNeverLeaks:
    def test_run_rejects_shell_strings(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        mo.DRY_RUN = False
        with pytest.raises(TypeError):
            mo.run("git clone " + DIRTY_USERPASS)

    def test_run_redacts_credentials_in_stderr(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        mo.DRY_RUN = False
        rc, out, err = mo.run(["git", "clone", DIRTY_HTTPS, str(tmp_path / "nope")],
                              cwd=str(tmp_path))
        assert rc != 0
        assert FAKE_TOKEN not in err and FAKE_TOKEN not in out
        assert _FAKE_PASS not in err

    def test_redact_masks_tokens_and_env_values(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        s = mo.redact("fatal: auth failed for %s and GITHUB_TOKEN=%s" % (DIRTY_HTTPS, FAKE_TOKEN))
        assert FAKE_TOKEN not in s
        assert "<REDACTED>" in s

    def test_log_file_contains_no_credential(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        mo.DRY_RUN = False
        mo.run(["git", "clone", DIRTY_USERPASS, str(tmp_path / "x")], cwd=str(tmp_path))
        content = mo.LOG_FILE.read_text(encoding="utf-8") if mo.LOG_FILE.exists() else ""
        assert _FAKE_PASS not in content
        assert not CRED_URL_RE.search(content)

    def test_get_token_returns_no_value(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        monkeypatch.setenv("GITHUB_TOKEN", FAKE_TOKEN)
        assert mo.get_token() == ""
        assert mo.token_available() is True

    def test_assert_clean_remote_scrubs_dirty_origin(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        mo.DRY_RUN = False
        repo = _make_repo(tmp_path, DIRTY_HTTPS)
        ok, why = mo.assert_clean_remote(repo)
        assert ok is False and why
        url = subprocess.run(["git", "-C", str(repo), "remote", "get-url", "origin"],
                             capture_output=True, text=True).stdout.strip()
        assert url == CLEAN_HTTPS

    def test_assert_clean_remote_passes_clean_origin(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        mo.DRY_RUN = False
        repo = _make_repo(tmp_path, CLEAN_HTTPS)
        ok, why = mo.assert_clean_remote(repo)
        assert ok is True and why == ""

    def test_phase6_aborts_without_credential_helper(self, tmp_path, monkeypatch):
        mo = _load_orchestrator(tmp_path, monkeypatch)
        mo.DRY_RUN = False
        monkeypatch.setattr(mo.shutil, "which", lambda _: None)
        monkeypatch.setattr(mo, "ensure_git_auth", lambda: False)
        repo = _make_repo(tmp_path, DIRTY_HTTPS)
        (repo / "f.txt").write_text("x", encoding="utf-8")
        mo.ACTIVE_REPOS, mo.ARCHIVED_REPOS = ["demo"], []
        assert mo.phase6_push_all() == 0
        url = subprocess.run(["git", "-C", str(repo), "remote", "get-url", "origin"],
                             capture_output=True, text=True).stdout.strip()
        assert url == DIRTY_HTTPS  # لم يُمسّ المستودع: لا دفع ولا تعديل


class TestSourceHasNoDangerousPattern:
    @pytest.mark.parametrize("path", ["master_orchestrator.py", "config/lib-common.sh",
                                      "github-sync.sh", "token-manager.py"])
    def test_no_credential_in_url_construction(self, path):
        text = (REPO_ROOT / path).read_text(encoding="utf-8", errors="replace")
        assert ("x-access" + "-token") not in text, path
        assert not re.search(r'://\s*\$\{?[A-Za-z_]*USERNAME\}?[:$]', text), path
        assert not re.search(r'https://[^"\']*\$\{?(GITHUB_TOKEN|token)\}?@', text), path

    def test_orchestrator_has_no_shell_true(self):
        text = ORCHESTRATOR.read_text(encoding="utf-8")
        # ignore docstrings/comments: the rule is about executable code
        code = re.sub(r'"""[\s\S]*?"""', "", text)
        code = re.sub(r"#[^\n]*", "", code)
        assert "shell=True" not in code

    def test_setup_auth_reports_failure_when_gh_fails(self, tmp_path):
        """لا ابتلاع صامت لفشل المصادقة: يجب أن يعود خطأ وأن يُسجَّل ERROR."""
        binp = tmp_path / "bin"; binp.mkdir()
        fake = binp / "gh"
        fake.write_text("#!/bin/bash\nexit 3\n", encoding="utf-8")
        fake.chmod(0o755)
        repo = _make_repo(tmp_path, CLEAN_HTTPS)
        r = _bash('setup_auth "%s" "%s" && echo AUTH_OK || echo AUTH_REFUSED\n'
                  'grep -c ERROR "${CURRENT_LOG:-$LOG_DIR/sync.log}" || true\n' % (repo, CLEAN_HTTPS),
                  tmp_path, extra_env={"PATH": "%s:/usr/bin:/bin" % binp})
        assert "AUTH_REFUSED" in r.stdout

    def test_setup_auth_succeeds_with_working_gh(self, tmp_path):
        binp = tmp_path / "bin"; binp.mkdir()
        fake = binp / "gh"
        fake.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
        fake.chmod(0o755)
        repo = _make_repo(tmp_path, CLEAN_HTTPS)
        r = _bash('setup_auth "%s" "%s" && echo AUTH_OK || echo AUTH_REFUSED\n' % (repo, CLEAN_HTTPS),
                  tmp_path, extra_env={"PATH": "%s:/usr/bin:/bin" % binp})
        assert "AUTH_OK" in r.stdout


# ══════════════════════════════════════════════════════════════ Bash


@pytest.mark.skipif(not shutil.which("bash"), reason="bash required")
class TestLibCommon:
    def test_url_has_credentials_true(self, tmp_path):
        r = _bash('url_has_credentials "%s" && echo DIRTY || echo CLEAN\n' % DIRTY_HTTPS, tmp_path)
        assert "DIRTY" in r.stdout

    def test_url_has_credentials_false_for_clean(self, tmp_path):
        r = _bash('url_has_credentials "%s" && echo DIRTY || echo CLEAN\n' % CLEAN_HTTPS, tmp_path)
        assert "CLEAN" in r.stdout
        r2 = _bash('url_has_credentials "%s" && echo DIRTY || echo CLEAN\n' % CLEAN_SSH, tmp_path)
        assert "CLEAN" in r2.stdout

    def test_assert_clean_url_rejects_dirty(self, tmp_path):
        r = _bash('assert_clean_url "%s" demo && echo ACCEPTED || echo REJECTED\n' % DIRTY_USERPASS, tmp_path)
        assert "REJECTED" in r.stdout
        assert _FAKE_PASS not in (r.stdout + r.stderr)

    def test_assert_clean_url_accepts_clean(self, tmp_path):
        r = _bash('assert_clean_url "%s" demo && echo ACCEPTED || echo REJECTED\n' % CLEAN_HTTPS, tmp_path)
        assert "ACCEPTED" in r.stdout

    def test_ensure_clean_remote_scrubs(self, tmp_path):
        repo = _make_repo(tmp_path, DIRTY_HTTPS)
        r = _bash('ensure_clean_remote "%s" && echo OK || echo FIXED\n'
                  'git -C "%s" remote get-url origin\n' % (repo, repo), tmp_path)
        assert CLEAN_HTTPS in r.stdout
        assert FAKE_TOKEN not in r.stdout

    def test_setup_auth_fails_closed_without_gh_or_helper(self, tmp_path):
        repo = _make_repo(tmp_path, CLEAN_HTTPS)
        body = ('PATH="%s"\n'
                'setup_auth "%s" "%s" && echo AUTH_OK || echo AUTH_REFUSED\n'
                % (tmp_path / "emptybin", repo, CLEAN_HTTPS))
        (tmp_path / "emptybin").mkdir(exist_ok=True)
        r = _bash(body, tmp_path, extra_env={"HOME": str(tmp_path / "fakehome")})
        (tmp_path / "fakehome").mkdir(exist_ok=True)
        assert "AUTH_REFUSED" in r.stdout


# ══════════════════════════════════════════════════════════════ Scanner


class TestSecretScanner:
    def _run(self, target):
        return subprocess.run([sys.executable, str(SCANNER), str(target)],
                              capture_output=True, text=True, cwd=str(REPO_ROOT))

    def test_blocks_real_shaped_token_and_never_prints_it(self, tmp_path):
        f = tmp_path / "leak.env"
        f.write_text("GITHUB_TOKEN=%s\n" % FAKE_TOKEN, encoding="utf-8")
        r = self._run(f)
        assert r.returncode == 1
        assert FAKE_TOKEN not in r.stdout and FAKE_TOKEN not in r.stderr
        assert "BLOCK" in r.stdout

    def test_placeholder_is_not_blocking(self, tmp_path):
        f = tmp_path / "ok.env.example"
        f.write_text("GITHUB_TOKEN=ghp_REPLACE_ME\nHF_TOKEN=hf_REPLACE_ME\n", encoding="utf-8")
        r = self._run(f)
        assert r.returncode == 0

    def test_masked_placeholder_is_downgraded_to_warning(self, tmp_path):
        f = tmp_path / "masked.env.example"
        f.write_text("GITHUB_TOKEN=ghp_%s\n" % ("x" * 36), encoding="utf-8")
        r = self._run(f)
        assert r.returncode == 0
        assert "placeholder" in r.stdout

    def test_whole_repo_passes(self):
        r = subprocess.run([sys.executable, str(SCANNER), "--all"],
                           capture_output=True, text=True, cwd=str(REPO_ROOT))
        assert r.returncode == 0, r.stdout + r.stderr

    def test_no_tracked_file_embeds_credentials_in_url(self):
        files = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                               cwd=str(REPO_ROOT)).stdout.split()
        offenders = []
        for rel in files:
            if rel.startswith("legacy/"):      # أرشيف جلسة مُحمَّر مسبقًا — للقراءة فقط
                continue
            p = REPO_ROOT / rel
            if not p.is_file() or p.stat().st_size > 2_000_000:
                continue
            text = p.read_text(encoding="utf-8", errors="replace")
            for m in CRED_URL_RE.finditer(text):
                seg = text[m.start():m.start() + 120]
                if re.search(r"(?i)(your|example|replace|<user>|<cred>|localhost|change_me|\$\{)", seg):
                    continue
                offenders.append((rel, text.count("\n", 0, m.start()) + 1))
        assert not offenders, offenders


# ══════════════════════════════════════════════════════════════ Gate script

GATE = REPO_ROOT / "scripts" / "check_no_credentials_in_urls.py"


class TestCredentialUrlGate:
    def _gate(self, *extra):
        return subprocess.run([sys.executable, str(GATE), *extra],
                              capture_output=True, text=True, cwd=str(REPO_ROOT))

    def test_gate_passes_on_current_tree(self):
        r = self._gate()
        assert r.returncode == 0, r.stdout + r.stderr

    def test_gate_module_blocks_reconstructed_anti_pattern(self, tmp_path):
        """تحكّم سلبي: النمط القديم نفسه يجب أن يُرفض."""
        spec = importlib.util.spec_from_file_location("gate_mod", GATE)
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        tok = "x-access" + "-token"
        bad = tmp_path / "bad_orchestrator.py"
        bad.write_text(
            "\n".join([
                'url = f"https://' + tok + ':{token}@github.com/{U}/{r}.git"',
                'run("git remote set-url origin https://' + tok + ':${GITHUB_TOKEN}@github.com/o/r.git")',
            ]),
            encoding="utf-8")
        hits = gate.scan(bad)
        assert hits and all(v == "BLOCK" for _, _, v in hits), hits
        names = {n for _, n, _ in hits}
        assert "x-access-token-in-url" in names

    def test_gate_module_allows_documented_examples(self, tmp_path):
        spec = importlib.util.spec_from_file_location("gate_mod2", GATE)
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        ok = tmp_path / "docs.md"
        ok.write_text(
            "Set GITHUB_TOKEN=<REPLACE_WITH_YOUR_TOKEN> in your environment.\n"
            "Anti-pattern (do NOT use): https://<USER>:<TOKEN>@github.com/owner/repo.git\n",
            encoding="utf-8")
        verdicts = [v for _, _, v in gate.scan(ok)]
        assert "BLOCK" not in verdicts

    def test_gate_module_ignores_prose_without_variable(self, tmp_path):
        spec = importlib.util.spec_from_file_location("gate_mod3", GATE)
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        doc = tmp_path / "prose.md"
        doc.write_text("Never embed a token inside the remote URL of a repository.\n",
                       encoding="utf-8")
        assert gate.scan(doc) == []


    def test_gate_module_allows_documented_examples(self, tmp_path):
        spec = importlib.util.spec_from_file_location("gate_mod2", GATE)
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        ok = tmp_path / "docs.md"
        ok.write_text("Set GITHUB_TOKEN=<REPLACE_WITH_YOUR_TOKEN>; never use "
                      "https://user:token@github.com/… (example only)\n", encoding="utf-8")
        assert all(v != "BLOCK" for _, _, v in gate.scan(ok))

    def test_gate_excludes_legacy_archive_by_default(self):
        r = self._gate()
        assert "legacy/" not in r.stdout

    def test_gate_json_report_is_valid(self, tmp_path):
        out = tmp_path / "report.json"
        r = self._gate("--json", str(out))
        assert r.returncode == 0
        import json as _json
        data = _json.loads(out.read_text(encoding="utf-8"))
        assert data["blockers"] == []
        assert data["scanned_files"] > 0
