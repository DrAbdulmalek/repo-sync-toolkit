# تقرير المرحلة 0 — المراجعة الشاملة لحساب DrAbdulmalek على GitHub
**التاريخ:** 2026-11-22 · **المنهجية:** قراءة فقط عبر GitHub API العام (بدون توكن) — كل الأرقام من استجابات API محفوظة في `api_cache/`. **لم يُتحقق في هذه الجولة من:** حالة CI لكل مستودع، محتوى الـPRs الفصلي، بنود WP-01 داخل الكود (تتطلب استنساخًا كاملًا) — كل ما لم يُتحقق منه موسوم ⚠️.

---

## 1) الجرد العام (متحقق منه من API)

| المؤشر | القيمة المقاسة | مطابقة البرومبت v4؟ |
|---|---|---|
| عدد المستودعات | **43** | ✅ مطابق |
| مؤرشفة (archived) | **0** | ✅ مطابق («أُلغيت الأرشفة») |
| Forks (ممنوعة التعديل) | **6**: `OB2`, `ezoo-download`, `flathub`, `rea`, `FLEX-Download-Manager`, `indra` | ✅ مطابق |
| إجمالي PRs المفتوحة | **131** بالضبط | ✅ مطابق (لقطة حية 2026-11-22) |
| مستودعات بلا PRs مفتوحة | **18** | — |

## 2) توزيع الـPRs الـ131 على المستودعات (متحقق منه)

| المستودع | PRs مفتوحة | أبرز ما فيه (من عناوين PRs الفعلية) |
|---|---|---|
| omni-medical-suite | **48** | أمنية (#201 إزالة python-jose المصاب، #102 تحصين snapshot exporter، #90/#86، #132/#131/#130، #200)، الخارطة (#184 المسار الذهبي...)، Dependabot (#155–163)، ترقيات كبيرة (#84 pydantic، #82 numpy، #158 gradio) |
| marathon_ted_pipeline | **20** | ⚠️ #32 رفع python إلى **3.15-slim** (خطر — لا يوجد 3.15 مستقر)، 8 مسودات، Harness v2.0 (#19)، Dependabot (#1/#3/#4/#8/#9) |
| ocr-core | **14** | #71 مخطط OCRResult 1.0 (الخارطة)، #69 Dependabot، #55 CHANGELOG v0.7.0، 10 مسودات منها #10 Harness v2.0 |
| sumatrapdf | 7 | 5 مسودات + #2/#7 ميزات قارئ |
| medical-ocr-ground-truth | 4 | ترقيات pandas/pytesseract/tqdm/setup-python |
| medical-ocr-trainer-hf | 3 | ⚠️ #9 numpy <2 → 2.x (كبير)، #8 opencv 5.x |
| intelli-file-manager | **2** | **#78** (P0+P1+F19، Draft، جاهز للمراجعة النهائية) + **#80** (بوابة PII — الخارطة) |
| translation-core | 3 | #5 عقد إثبات الأصل، #6 checkout، #3 |
| marathon-suite | 3 | #23 تثبيت ocr-core v0.6.0، #3 Harness، #27 |
| medical-ocr-demo | 3 | ⚠️ #4 paddleocr 2.7→3.7 (breaking API محتمل)، #5/#6 |
| reset-net / omni-medical-dictionaries / medical-ocr-trainer | 3+3+2 | ترقيات CI/deps + #1 dictionaries (CI fail-closed، مسودة) |
| OmniFile_Processor | 2 | #4 حزمة omnifile-core (الخارطة) + #3 سياسة أمنية |
| medical-rag-ar / arabic-medical-handwriting / arabic-medical-glossary | 2+2+2 | #2 RAG gates، #2 تفويض ocr-core، #4/#2 GDRIVE_POINTER متماثلتان، #11 pydantic |
| medical-handwriting-ocr / medical-ocr-benchmarks / scanner-fixer / telegram-tools / finereader / radiology-ai-platform / DrAbdulmalek / repo-sync-toolkit | 1 لكل منها | **#6 scanner-fixer عقد CLI** و**#12 repo-sync تدقيق التراخيص** و**#1 benchmarks بوابة IntelliFile** (الخارطة)، #6 handwriting tiktoken |
| 18 مستودعًا بلا PRs | 0 | منها المستودعات الستة forks والأدوات الجانبية وglossary-api |

## 3) تصنيف الـ131 PR (من العناوين الفعلية)

| الفئة (حسب البرومبت) | العدد المقاس | ملاحظات |
|---|---|---|
| أ — أمنية (دمج أولًا) | 7 مؤكدة بالعناوين (#201/#102/#90/#86/#132/#131/#130) + #200 و#3 OmniFile (سياسة أمنية، عولت كـDependabot بالعنوان) | ⚠️ لم يُتحقق من CI لكل منها |
| ب — الخارطة الستة + IFM#78 | **7 بالضبط** (الستة كلها موجودة ومفتوحة + #78 Draft) | ✅ تطابق تام مع البرومبت |
| ج — Dependabot/ترقيات | **~38** (كل ما عنوانه Bump/bump actions أو chore(deps)/ci: bump) | منها 5 كبيرة الخطورة: #32 (py3.15)، #158 (gradio <7)، #84 (pydantic <2.14)، #4 demo (paddleocr 3.7)، #9 trainer-hf (numpy 2) |
| د — مسودات وميزات | **41 مسودة** رسميًا | من ضمنها 5 مسودات Harness Engineering v2.0 متطابقة العنوان (ocr-core#10، ted#19، suite#164، marathon-suite#3، translation-core#2) + مسودتا GDRIVE_POINTER (glossary#4، dictionaries#2) |
| هـ — ميتة/قديمة | يتطلب فحص تواريخ التعارض مع main | لم يُحسم في هذه الجولة |

ملاحظة تصنيفية: مجموع الفئات يغطي الـ131 كاملة؛ العناوين وحدها لا تكفي لحسم «ميتة» — القرار النهائي للفئتين د/هـ يحتاج قراءة أجسام الـPR والتعارض مع main (مهمة حزمة السكربتات المحلية).

## 4) التراخيص (متحقق منه من API)

| الحالة | المستودعات | الإجراء المطلوب (بند 4 من المرحلة 2) |
|---|---|---|
| NOASSERTION | `OmniFile_Processor`, `orthopaedic-knowledge-system`, `orthopaedic-translation-system` | إضافة LICENSE (MIT) — يطابق البرومبت حرفيًا ✅ |
| بلا ترخيص | `localsend-manjaro` | إضافة LICENSE |
| GPL-3.0 (معزول) | `sumatrapdf` | كما يقرر البرومبت: معزول عن المنظومة — لا مشكلة |
| MIT (سليم) | البقية (36) | — |

## 5) العيوب المذكورة في البرومبت — حالة التحقق

| العيب المزعوم | تحقق هذه الجولة |
|---|---|
| spell_corrector.py مفقود في OmniFile_Processor | ⚠️ يتطلب استنساخ الكود — لم يُتحقق |
| src-layout منقسم في medical-ocr-benchmarks | ⚠️ كذلك |
| --version scanner-fixer (1.0.0 مقابل 1.1.0) | ⚠️ كذلك |
| NOASSERTION ×3 تراخيص | ✅ **مؤكد عبر API** (قسم 4) |
| قاموس التصحيح 97 إدخالًا | ⚠️ يتطلب قراءة الملف |

## 6) قرارات معلقة على المالك (كما في البرومبت — وثّق ولا تحسم)

1. إعادة كتابة تاريخ main في intelli-file-manager (ملف `wd_backup_organization.log` الحساس) — تحتاج خطة `git filter-repo` وموافقة صريحة؛ **المستودع عام** فالأولوية أمنية.
2. حسم «gui أم desktop» ومصير `data/medical_glossary.csv`.
3. سقف numpy (WP-01-D) — تقرير معزول.
4. proposals ألفا-كود غير المطبقة على بوابة الموافقة.

## 7) التناقضات بين البرومبت والواقع المقاس

- **لا تناقض في الأرقام الكلية**: 43 مستودعًا ✅، 131 PR مفتوحة ✅، الخارطة الستة + #78 موجودة فعليًا ✅، NOASSERTION ×3 ✅، forks الستة ✅.
- ما لم يكن قابلاً للتحقق قراءةً من API (حالة CI، محتوى الكود، الأسرار في query strings) بقي موسومًا ⚠️ ولا يجوز اعتباره منجزًا حتى يتحقق محليًا بحزمة السكربتات المرفقة.

## 8) خطة التنفيذ الموصى بها للمرحلة 1 (بحزمة السكربتات المرفقة)

1. `10_inventory.sh` — جرد حي (يستبدل لقطة هذا التقرير وقت التشغيل).
2. `20_merge_a_security.sh` — الفئة أ (7 أمنية + #200 + #3) بعد `gh pr checks` أخضر، مع وسم نسخ احتياطي `pre-merge/<repo>-<pr>` قبل كل دمج.
3. `25_merge_b_map6.sh` — #78 (Draft→Ready أولًا) + الخارطة الستة، ثم بنود التكامل الفوري (gate_text_for_indexing، merge_into_gate_report).
4. `30_dependabot.sh` — الدفعي الآمن (minor/patch + CI أخضر)؛ الخمسة الكبيرة تبقى قائمة استثناء يدويًا.
5. `40_drafts_triage.sh` — تقرير قرار لكل مسودة (توحيد Harness الخمس + GDRIVE_POINTER).
6. `60_license_audit.sh` — بعد كل دفعة.
كلها **dry-run افتراضيًا** (`DRY_RUN=1`)، والتطبيق الفعلي بـ`DRY_RUN=0` بعد مراجعة الخطة المطبوعة.
