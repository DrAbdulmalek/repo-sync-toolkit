# تقرير جولة التنفيذ الفعلي — المرحلة 1 (دمج الـ131 PR)

**التاريخ:** 2026-11-23 | **المنفذ:** وكيلاً عن المالك (تفويض "تابع العمل") | **الحزمة:** `phase1/ortho-ecosystem-phase0` (v4) من `repo-sync-toolkit@main` (c710358)

## الخلاصة

| المقياس | العدد |
|---|---|
| دموجات فعلية موثقة في الجدول | **27** (25 في هذه الجولة + IFM#78 وrst#13 في الجولة السابقة) |
| الفئة أ — الأمنية P0 | **4/4** القابلة للدمج (البقية متعارضة — انظر أدناه) |
| الفئة ب — الخارطة | **2/6** (البقية CI فاشل فعليًا أو بلا CI) |
| الفئة ج — الاعتماديات | **19** دمج squash من 46 آمنة؛ الخمسة الكبيرة مستثناة دائمًا |
| متوقف fail-closed موثق بسبب | **36** |
| مستثنى (خطورة عالية) | **5** (ted#32، suite#158، suite#84، demo#4، trainer-hf#9) |

## الفئة أ — الأمنية (P0): مكتملة بالكامل للقابلة

عبر بوابة CI الأخضر + النسخة الاحتياطية (manifest + JSON) + تحديث الفرع وسلسلة strict:

| PR | الشهادة | المسار التنفيذي |
|---|---|---|
| suite#201 إزالة python-jose (PYSEC-2026-4298) | merge sha `21d0f2b` | دمج مباشر (فرع محدث) |
| suite#86 إغلاق ثغرات ما بعد 85 | merge sha `6cdc469` | تحديث فرع → CI 25/25 → دمج |
| suite#131 SEC-2 env token-shape guard | merge sha `edf7081` | تحديث فرع → CI 8/8 مطلوبة → دمج |
| suite#130 حجر Telegram Forwarder | merge sha `4e768d1` | تحديث فرع → CI 23/23 → دمج |

**المتبقية أمنية (مفتوحة، لا تُغلق):** #102 و#132 متعارضتان فعليًا مع main (`mergeable=False, dirty`) — تحتاج حل تعارض يدويًا؛ #90 فحصها المطلوب `Apply verified security fixes` فاشل + متعارضة. الفحص المستعرض (أسرار في query strings على 8 مستودعات أساسية): نظيف — كل الإصابات مطابقات كود (`token=token`) وليست أسرارًا حرفية.

## الفئة ب — الخارطة

- **intelli-file-manager#80 (بوابة PII): مدموج** ✓ — بند التكامل (a) `gate_text_for_indexing(text, source=str(path))` في `RAGEngine.ingest_file` يُطبق الآن كـPR صغير منفصل (قاعدة مسار PR الإلزامية).
- **ocr-core#71: مدموج** ✓.
- **OmniFile_Processor#4، scanner-fixer#6، medical-ocr-benchmarks#1:** CI فاشل فعليًا على رؤوسها (Lint/Core Tests/Test) — إصلاح كود مطلوب قبل الدمج؛ البوابة رفضت fail-closed.
- **repo-sync-toolkit#12:** المستودع **بلا CI نهائيًا** (صفر فحوص) — بوابة CI لا يمكن أن تمر ميكانيكيًا؛ قرار مالك: إضافة سير عمل CI ثم إعادة التقييم، أو دمج يدوي موثق. حتى ذلك، تدقيق التراخيص (60) سجل: `license_audit.py` غير متاح على main + NOASSERTION الحية: localsend-manjaro، OmniFile_Processor، ortho-align، orthopaedic-knowledge-system، orthopaedic-translation-system.

## الفئة ج — الاعتماديات (الدفعي الآمن)

**19 مدموجًا squash:** telegram-tools#16، translation-core#6، medical-rag-ar#3، arabic-medical-handwriting#5، omni-medical-dictionaries#9، arabic-medical-glossary#11، marathon-suite#27، ocr-core#69، marathon_ted_pipeline#35/#34/#9/#8/#4/#3/#1، medical-ocr-trainer-hf#13/#12/#11/#4.

**15 رفض CI مصنف السبب:**
- بلا CI إطلاقًا (قرار ملك لكل منها): radiology-ai-platform#5، medical-ocr-demo#5/#6.
- Lint فاشل فعليًا (الفرع ليس خلفيًا — تحقق حي): medical-ocr-trainer#5/#6، medical-ocr-ground-truth#12–15.
- اختبارات فاشلة: medical-handwriting-ocr#6 (build-android أيضًا)، reset-net#3–5 (Test on Arch)، suite#83 (Matrix Summary).

**suite الاعتماديات (10):** #161/#160/#157/#156/#155/#107/#82/#81/#78 خلفية بفعل الحماية الصارمة — **انطلقت تحديثات فروعها التسع ~09:05 وCI يعمل بالتوازي**؛ الدمج **تسلسلي إلزامي** (strict up-to-date + enforce_admins): يُدمج الأول حين يخضر، ثم تُحدَّث البقية ويعاد CI، وهكذا. #159 متعارضة فعليًا (حل يدوي).

## الفئة د — المسودات (تقرير قرار، لا إغلاق آلي)

41 مسودة مصنفة: **5 مكررات Harness Engineering v2.0** (المقترح: ocr-core#10 مرجعيًا)؛ **2 متماثلتان GDRIVE_POINTER** (المقترح: glossary#4 مرجعي وإغلاق dictionaries#2)؛ والبقية (sumatrapdf#1/#3/#4/#5/#6، ocr-core#11/#12/#57–#68، suite#195–#199…) قرار لكل واحدة: إنهاء/دمج/إغلاق — تحتاج قرار المالك.

## إصلاحات الحزمة الموثقة (مرفوعة في هذا الـPR)

1. `lib.sh`: صيغة gh v2.105 (`--repo OWNER/REPO NUM` بدل `OWNER/REPO#NUM`) + فحص CI لحظي بدل `--watch` (نفس البوابة fail-closed؛ المعلق يُسجل ويعاد) + `run()` يوثق الفشل بصدق (`EXEC-FAILED`) بدل سطر MERGED الزائف.
2. `30_dependabot.sh`: إصلاح حلقة الدمج (`for $(...)` كانت تقسم على كلمات فتموت `$2` تحت `set -u` → قراءة سطرًا سطرًا).
3. `20_merge_a_security.sh` و`25_merge_b_map6.sh`: صيغة gh الجديدة + تخطي IFM#78 (مدموج مسبقًا 90b38f0).

## الالتزامات الملاحظة

- لا دفع مباشر إلى main في أي مستودع؛ الدموجات عبر واجهة PR فقط. لا إغلاق PR، لا forks، لا إعادة كتابة تاريخ، لا كتابة على `alphacode/artifacts`. التوكن من البيئة فقط ولم يُطبع أو حُفظ في أي ملف.
- كل دمج سبقته نسخة احتياطية (manifest + JSON الـPR) ووسم `pre-merge/pr-N` عند توافر نسخة محلية.
- سجل التنفيذ الكامل: `logs/phase1_run_*.log` + مخرجات الفئات مرفقة في هذا الـPR.

## ما تبقى (برومبت المتابعة v5 يغطيه)

1. حل تعارضات الأمنية الثلاث suite#102/#132/#90 (حل يدوي ثم CI ثم دمج).
2. إكمال سلسلة suite الاعتماديات التسع (تسلسلي strict؛ التحديثات انطلقت).
3. إصلاحات Lint/Tests للـPR الفاشلة فعليًا (trainer، ground-truth، handwriting، reset-net، OmniFile#4، scanner-fixer#6، benchmarks#1، suite#83).
4. قرار بلا-CI: rst#12، radiology#5، demo#5/#6 (إضافة CI أو دمج يدوي).
5. قرارات المسودات (الفئة د) والخمسة الكبيرة وبنود هـ، وبندا التكامل الفوري (a)/(b) كـPRs صغيرة.
