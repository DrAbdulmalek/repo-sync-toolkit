# تقرير التنفيذ — الخطوة التالية المنطقية (2026-11-25)

تنفيذ أمرين وفق التسلسل المعتمد في issues-pack README: **تفعيل بوابة العقد (ocr-core#73)** و**بدء المهمة الصفرية (repo-sync-toolkit#15)**. النشر استخدم التوكن المؤقت المقدم — **انتهى غرضه ويجب إبطاله فورًا** (يمتلك push/admin).

---

## 1) بوابة العقد — ocr-core#73: ✅ مفعّلة ومكتملة

**المسار:** جرد فعلي → اكتشاف أن جزءًا من البوابة منجز (PR #71/schema 1.0 + LICENSE MIT من الالتزام الأول) → تنفيذ **الفجوات فقط** → CI أخضر → PR #78 → دمج `d187f4bc` → إغلاق #73 بالتوثيق.

| مهمة الإشوه | التنفيذ |
|---|---|
| contract.md | `docs/CONTRACT.md` (من #71) + **سياسة التغيير** (4 قواعد) + **المثال النموذجي JSON** + **جدول المستهلكين الثلاثة** |
| اختبارات ذهبية | `tests/test_contract.py` (11 اختبارًا) + `tests/golden_contract_signature.json` ذاتية التحقق بـsha256 — تلتقط العقد من الكود الحقيقي (0.7.0) |
| LICENSE MIT | كانت منجزة — أضيف لها حارس `test_license_is_mit` |
| CI: رفض اللمس دون major bump | `contract-guard.yml` + `scripts/ci/contract_guard.py` (stdlib) — اختُبر محليًا بمساريه، ونجح على CI |

- **pytest: 25/25 أخضر** محليًا؛ وعلى CI: `tests` ✓ `Contract Guard` ✓ `Secret Gate` ✓
- **البوابة طُبقت على نفسها**: 0.7.0 → **1.0.0** (CHANGELOG موثق)
- روابط: [PR #78](https://github.com/DrAbdulmalek/ocr-core/pull/78) · [إغلاق #73](https://github.com/DrAbdulmalek/ocr-core/issues/73#issuecomment-7148746010)

## 2) المهمة الصفرية — repo-sync-toolkit#15: ✅ بدأت (الأرشفة مؤجلة عمدًا لقرار المالك)

**الجرد الحي:** 45 مستودعًا (صفر مؤرشف، 6 مفروع، كلها عامة) + 9 أصول HF — [census JSON](./census_github_2026-11-25.json).

**النتيجة المحورية:** كل الـ45 دُفعت خلال آخر 34 يومًا (استعادة جماعية 13–23 نوفمبر) ⇒ معيار «6 أشهر» لا ينتج شيئًا؛ التصنيف على **أدلة الاستهلاك الفعلي** كما ينص الإشوه:

- **يبقى 15**: نواة الخطة الـ9 + glossary/glossary-api/telegram-tools + marathon-suite + marathon_ted_pipeline + الملف الشخصي
- **مرشح أرشفة 15 (بأدلة)**: 5 مفروع · scanner-fixer + medical-ocr-benchmarks (امتصتهما النواة) · عائلة medical-ocr-* (غلبها النواة/AMH) · baseline + finereader-analysis · workspace-scripts-archive
- **مراجعة 15 (سؤال قرار لكل واحد)**: أدوات manjaro النشطة، المشاريع الحية، atlas/ponytail، flathub (أرشفته تقتل إشوهاته)

**المخرجات في PR #17** (فرع `task-zero/inventory-manifest`):
- `manifest.json` (جذر): بيان §8.2 كامل — 45 مستودعًا + 9 أصول HF بوسوم keep-private/publish-after-scrub/archive
- `INVENTORY.md`: تقرير الجرد + سياسة الرموز §8.3 + سجل قرارات المالك + خريطة معايير القبول
- `archive_repos.py`: أداة مؤمّنة — dry-run افتراضي، `--apply` يتطلب `--confirmed` **و**قرارًا موثقًا في INVENTORY.md (الأقفال الثلاثة اختُبرت)، إعادة تشغيل آمنة، الرمز لا يُطبع

**لا مستودع أُرشف** — شرط الإشوه: توثيق قرار المالك أولًا.

## 3) اكتشافات مهمة (موثقة في الإشوهات/الـPRs)

1. **عاجل**: HF dataset `arabic-medical-ocr-corrections` **عام غير gated بـ28 تنزيلًا** — يتطابق مع ocr-core#76 (OCR-04). يُنصح بالمعالجة قبل الأرشفة.
2. `config/repos.txt` (2026-06-28) يضم 10 مستودعات حُذفت — قديم؛ و`ECOSYSTEM_STATE.md` يعدّ 9 فقط — كلاهما يحتاج تحديثًا منفصلًا.
3. لبس الترقيم السابق انحل: `#78` في ocr-core كان رقم PR (المشترك مع القضايا)، ولم يكن إشوهًا مكررًا.

## 4) متبقٍ على المالك

1. **إبطال التوكن المؤقت الآن** (انتهى غرضه).
2. مراجعة ودمج PR #17 (المهمة الصفرية) — ثم ملء سجل القرارات وتشغيل الأرشفة.
3. مواءمة ocr-core#75 (v0.5.0) مع خط 1.x.
4. قرار dataset التصحيحات على HF (gating فوري).

## الملفات المحلية (استرجاع دون شبكة)

| ملف | الوصف |
|---|---|
| `ocr-core-contract-gate.patch` / `.bundle` | التزام بوابة العقد (30a0840) — مطبق أصلاً على main |
| `repo-sync-toolkit-task-zero.patch` / `.bundle` | التزام المهمة الصفرية (079cb7d) — في انتظار دمج PR #17 |
| `census_github_2026-11-25.json` | الجرد الحي الخام |
