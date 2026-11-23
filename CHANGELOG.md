# CHANGELOG — repo-sync-toolkit

جميع التغييرات الملحوظة في هذا المشروع توثق هنا.
التنسيق مبني على Keep a Changelog، والإصدارات بتواريخ جولات العمل.

## [2026-11-23] جولة إصلاح 2 — إغلاق الثغرات الأربع من المراجعة المستقلة

### Changed
- **بوابة ما قبل الدمج** (`phase1/ortho-ecosystem-phase0/lib.sh` — `premerge_gate`): من العرض دون فحص إلى قائمة بيضاء صارمة ترفض صراحة: PR غير مفتوح (مغلق/مدموج مسبقًا)، `mergeable` غير `MERGEABLE` (يشمل CONFLICTING وUNKNOWN)، `mergeStateStatus` خارج {CLEAN, HAS_HOOKS} (يشمل DIRTY/BLOCKED/BEHIND/DRAFT/UNSTABLE)، مراجعة `CHANGES_REQUESTED`/`REVIEW_REQUIRED`، وفشل تحليل الاستجابة. فحص CI (`gh pr checks`) يعمل بعد تحليل الحالة.
- **النسخة الاحتياطية** (`backup_pr`): من لقطة بيانات فقط إلى نسخة مستقلة قابلة للاستعادة: `backups/bundles/pr_<repo>_<pr>.bundle` (git bundle كامل للرأس) مع `git bundle verify` من مستودع فارغ و**اختبار استعادة فعلي** (استنساخ من الـbundle + التحقق من وجود الـcommit) — وفشل أي خطوة يمنع الدمج. سطر الـmanifest يتضمن مسار الـbundle وحجمه. ملفات JSON أعيدت تسميتها `pr_meta_*` لتكون وصفها صادقًا (لقطات بيانات PR لا شيفرة).
- **المحاكي** (`tests/test_lib.sh`): يعمل بملف حالة ويحاكي انتقال الحياة الكامل: قبل الدمج `open`، بعد الدمج الناجح `closed+merged`، بعد الإغلاق `closed+unmerged`.

### Fixed
- **`close_pr`**: لم يعد يسجل CLOSED إلا بعد تحقق حي (state=closed من API)، ولا يصدر ادعاء نجاح في وضع DRY_RUN (يسجل DRY-RUN فقط).
- فحص CI داخل البوابة استُعاد بعد سقوطه في نسخة وسيطة — كشفه اختبارا T5/T6 قبل الرفع.

### Added
- 19 سيناريو اختبار (67 تأكيدًا) تشمل: فشل الدمج/البيانات/اللقطة، CI معلق وبلا فحوص، الدمج المزيف (exit 0 مع حالة مفتوحة)، دورة حياة OPEN→MERGED كاملة، رفض DIRTY/BLOCKED/CHANGES_REQUESTED/UNKNOWN/BEHIND وغير المفتوح قبل أي أمر دمج، فشل إنشاء الـbundle، وثلاثة مسارات إغلاق.
- `BACKUP_REMOTE_URL` كنقطة استبدال للمستودع البعيد في الاختبارات (أوامر git حقيقية بلا شبكة ولا توكن).
- `AI_WORKLOG.md` (هذا أول إدخال فيه يوثق الجولتين).

## [2026-11-23] جولة إصلاح 1 — إغلاق مسار MERGED الكاذب وبوابة النسخ الاحتياطي

### Fixed
- `merge_pr`: لا يسجل MERGED إلا بعد تحقق حي (state=closed + merged=true + merge_commit_sha) — أمر الدمج exit 0 وحده لا يكفي.
- `backup_pr` (الجولة 1): جلب بيانات PR من API موثوق + تحقق (غير فارغ + JSON صالح + رقم مطابق + sha رأس) + فشلها يمنع الدمج — سبب الإصلاح: 39/39 ملف نسخة احتياطية من الجولة الأولى كانت صفر بايت.
- `run()`: يوثق الفشل بصدق (EXEC-FAILED) ويعود برمز خروج غير صفري.
- صيغة gh v2.105: `--repo OWNER/REPO NUM` بدل `OWNER/REPO#NUM`.

### Added
- تدقيق حي للشهادات الـ27: 27/27 مؤكدة، صفر عدم تطابق (`phase1/reports/merge_certificates_audit_2026-11-23.md`) + تصحيح 3 شهادات ناقصة في `phase1/PR_merge_tracker.xlsx`.
- CI workflow (`phase1-scripts-ci`): ShellCheck بمستوى التحذير + الاختبارات على كل push/PR يمس `phase1/**`.
- ملحق الإصلاح الأول: `phase1/reports/gate_fix_addendum_2026-11-23.md`.
