# INVENTORY — جرد الأصول الكامل (المهمة الصفرية، issue #15)

> لقطة حية: 2026-11-25 — GitHub API (45 مستودعًا) + HuggingFace API (9 أصول)
> البيانات الخام: [`docs/census_github_2026-11-25.json`](./docs/census_github_2026-11-25.json) — تقرير تنفيذ هذه البوابة وما بعدها: [`docs/EXECUTION_REPORT_2026-11-25.md`](./docs/EXECUTION_REPORT_2026-11-25.md)
> التابع لـ: manifest.json (خطة §8.2) — الأرشفة الفعلية تُنفذ فقط بعد توثيق قرار المالك في هذا الملف (خطة §8.3 وشرط الإشوه #15)

## الملخص

| التصنيف | العدد | ملاحظة |
|---|---|---|
| **يبقى** (keep) | 15 | نواة الخطة الـ9 + منتجات/بيانات ECOSYSTEM_STATE + منسقان + الملف الشخصي |
| **مرشح للأرشفة** (archive-candidate) | 15 | أدلة: مفروع بلا استهلاك، أو وظيفة امتصتها النواة، أو أرشيف بحكم التعريف |
| **مراجعة** (review) | 15 | نشطة حديثًا أو دورها غير موثق — سؤال محدد لكل واحدة أدناه |

**لماذا لا يُعتمد «آخر push» وحده؟** كل الـ45 دُفعت بين 2026-10-22 و2026-11-25 (حدث استعادة/مزامنة جماعي 13–23 نوفمبر أعاد رفع تواريخ الكل) — لذا التصنيف على **أدلة الاستهلاك الفعلي**: من يمتصه ocr-core، من يستهلكه بمستند موثق (PR/إشوه)، وحكم ECOSYSTEM_STATE.md.

**تنبيه على المصادر القديمة:** `config/repos.txt` (2026-06-28) يضم 10 مستودعات حُذفت منذها (telegram-forwarder، telegram-channel-copier، telegram-pipeline، omniparse، omniparse-study، ai-fuel-engine، github-file-uploader، IntelliFile-app، medical-ocr-postprocessor، medical-doc-processor)، و`ECOSYSTEM_STATE.md` يعدّ 9 مستودعات فقط — كلاهما يحتاج تحديثًا في PR منفصل؛ هذا الجرد يَغِلب كليهما بوصفه لقطة حية.

## جدول الأرشفة الآمن (عند اعتماد المالك)

```bash
python3 archive_repos.py --dry-run      # العرض دون تغيير (الافتراضي)
python3 archive_repos.py --apply --confirmed   # فقط بعد توثيق قرار المالك أدناه
```


## يبقى — 15 مستودعًا (نواة + مستهلكون + منسقون + بيانات)

| المستودع | آخر push | الحجم | وسم §8.2 | دليل الاستهلاك | السبب/الإجراء |
|---|---|---|---|---|---|
| `DrAbdulmalek` | 2026-11-22 | 39 | publish-after-scrub | الملف الشخصي | يُبقى دائمًا |
| `arabic-handwriting-ocr-toolkit` | 2026-11-24 | 124 | publish-after-scrub | مستهلك أول للنواة + مصدر dataset التصحيحات | AHT-01 (#1): ترحيل محكوم إلى ocr-core@v0.x |
| `arabic-medical-glossary` | 2026-11-23 | 5,066 | publish-after-scrub | طبقة بيانات (ECOSYSTEM_STATE) | منتج بيانات نشط v1.0.0-rc1 |
| `arabic-medical-handwriting` | 2026-11-23 | 71 | publish-after-scrub | مستهلك للنواة (clean-room) | AMH-01 (#7) |
| `glossary-api` | 2026-11-23 | 79 | publish-after-scrub | طبقة API للمعجم (ECOSYSTEM_STATE) | منتج نشط |
| `intelli-file-manager` | 2026-11-24 | 19,031 | keep-private | المستهلك الرسمي الثاني لـcommon-core | IFM-01..03 (#91-93) — ECOSYSTEM_STATE: منتج للاستخدام الشخصي ⇒ keep-private |
| `marathon-suite` | 2026-11-23 | 543 | publish-after-scrub | منسق نحيف يثبّت ocr-core | قراءة واضحة: README = pins ocr-core |
| `marathon_ted_pipeline` | 2026-11-23 | 695 | publish-after-scrub | مستهلك موثق للنواة (ocr-core PR #14) | تكامل shim+pin مدمج في النواة |
| `medical-rag-ar` | 2026-11-23 | 26 | publish-after-scrub | مستهلك للنواة قبل الإطلاق | MRA-01 (#5) |
| `ocr-core` | 2026-11-25 | 3,474 | publish-after-scrub | toolkit/AMH/MRA/marathon_ted/marathon-suite | النواة المركزية — بوابة العقد #73 مفعّلة (PR #78) |
| `omni-medical-dictionaries` | 2026-11-23 | 1,015,142 | publish-after-scrub | بيانات القواميس | OMD-01 (#17): إزالة 1GB من git — HF Bucket المرجع الوحيد |
| `omni-medical-suite` | 2026-11-23 | 1,325,637 | publish-after-scrub | المنصة الأم — مصدر النوى المنقولة | OMS-01 (#203): أرشفة نهائية بعد جرد packages/* والنقل — مصيره موثق لا يُمس هنا |
| `repo-sync-toolkit` | 2026-11-23 | 792 | publish-after-scrub | هذه الأداة؛ وحدة الجرد المشتركة المستقبلية | RST-01 (#15) + RST-02 (#16): بذرة common-core |
| `telegram-tools` | 2026-11-23 | 288 | publish-after-scrub | مغذي بيانات التدريب (ECOSYSTEM_STATE) | أداة موحدة تَغِلب forwarder/copier/pipeline المحذوفة |
| `translation-core` | 2026-11-23 | 106 | publish-after-scrub | نواة ترجمة مستقلة | TC-01 (#8): قرار البقاء خارج نطاق الدمج موثق |


## مرشح للأرشفة — 15 مستودعًا بأدلة (قرار المالك مطلوب قبل التنفيذ)

| المستودع | آخر push | الحجم | وسم §8.2 | دليل الاستهلاك | السبب/الإجراء |
|---|---|---|---|---|---|
| `FLEX-Download-Manager` | 2026-10-25 | 208 | archive | fork | لا استهلاك في الخطة |
| `OB2` | 2026-11-20 | 1,126 | archive | fork | لا استهلاك في الخطة |
| `arabic-medical-ocr-baseline` | 2026-11-14 | 16 | archive | بطاقة نموذج مرجعية (وثيقة تاريخية) | قيمة توثيقية فقط — الأرشفة تحفظها للقراءة |
| `ezoo-download` | 2026-10-26 | 781 | archive | fork | لا استهلاك في الخطة |
| `finereader-ocr-apk-analysis` | 2026-11-14 | 62 | archive | تحليل هندسي عكسي ساكن | مرجع بحثي جامد — أرشفة مناسبة |
| `indra` | 2026-10-22 | 6,725 | archive | fork (نموذج OCR 1M param CPU) | مرجع بحثي؛ الأرشفة للقراءة تبقى ممكنة |
| `medical-handwriting-ocr` | 2026-11-22 | 738 | archive | غُلب بـarabic-medical-handwriting (clean-room) | AMH هي البديلة الموحدة |
| `medical-ocr-benchmarks` | 2026-11-22 | 202 | archive | غُلب بـocr-core benchmarks (ci_suite/بوابات CER-WER) | الكود حي في النواة |
| `medical-ocr-ground-truth` | 2026-11-22 | 130 | archive | دورة التصحيحات انتقلت (5a_correction_dict + dataset gated حسب OCR-04 #76) | يُتحقق من مصير بياناته ثم أرشفة |
| `medical-ocr-trainer` | 2026-11-22 | 254 | archive | غُلب بـocr-core commands/benchmarks + حلقة الجودة #77 | وظائفه منقولة للنواة |
| `medical-ocr-trainer-hf` | 2026-11-23 | 254 | archive | نشر Space لمدرّب غُلب | تابع لـmedical-ocr-trainer |
| `medical-ocr-training-hub` | 2026-11-14 | 87 | archive | حلقة التحسين امتصتها 3b_review + عتبات الجودة (#77) | وظائفه منقولة |
| `rea` | 2026-11-20 | 87,341 | archive | fork — الأصل محفوظ عند صاحبه | لا استهلاك في الخطة؛ الأرشفة لا تفقد الكود |
| `scanner-fixer` | 2026-11-22 | 15,051 | archive | امتصه ocr-core: preprocess.scanner_fixer | الكود حي في النواة؛ الأصل هنا مكرر بعد النقل |
| `workspace-scripts-archive` | 2026-11-14 | 395 | archive | لقطة أرشيفية بحكم التعريف | الأرشفة تجعله read-only محفوظًا كما هو |

**قاعدة التنفيذ:** لا يُؤرشف شيء من هذا القسم إلا بعد تسجيل «قرار المالك: معتمد — <القائمة>» في سجل القرارات أدناه.


## مراجعة — 15 مستودعًا (قرار مالك بلا دليل كافٍ)

| المستودع | آخر push | الحجم | وسم §8.2 | دليل الاستهلاك | السبب/الإجراء |
|---|---|---|---|---|---|
| `OmniFile_Processor` | 2026-11-22 | 722 | publish-after-scrub | علاقته بـocr-core/intelli غير واضحة | سابقة أو مستقلة؟ قرار مالك |
| `atlas-multi-provider` | 2026-11-20 | 40 | publish-after-scrub | بلا وصف — نشط 2026-11-20 | دوره غير موثق |
| `flathub` | 2026-10-26 | 602 | archive | fork مستخدم كمتتبع إشوهات للترقيات | الأرشفة تقتل الإشوهات — قرار مالك |
| `localsend-manjaro` | 2026-11-16 | 4 | publish-after-scrub | أداة نظام نشطة 2026-11-16 | استخدام يومي محتمل |
| `manjaro-care` | 2026-11-23 | 907 | publish-after-scrub | أداة نظام نشطة 2026-11-23 | استخدام يومي محتمل — خارج نطاق الدمج |
| `manjaro-doctor` | 2026-11-14 | 19 | publish-after-scrub | مرجع Manjaro نشط 2026-11-14 | مشروع منشور |
| `medical-ocr-demo` | 2026-11-23 | 65 | publish-after-scrub | نشط 2026-11-23 — Space مرتبط medical-ocr-demo | عرض حي: هل يبقى Face للمنظومة؟ |
| `ortho-align` | 2026-11-23 | 22 | publish-after-scrub | أداة مواءمة EN-AR (Orthobullets) | تغذي منظومة orthopaedic؟ |
| `orthopaedic-knowledge-system` | 2026-11-14 | 204 | publish-after-scrub | مشروع نشط 2026-11-14 | هل يستمر؟ |
| `orthopaedic-translation-system` | 2026-11-13 | 58 | publish-after-scrub | مشروع نشط 2026-11-13 | هل يستمر؟ |
| `radiology-ai-platform` | 2026-11-20 | 180 | publish-after-scrub | مشروع نشط 2026-11-20 | هل يستمر؟ |
| `reset-net` | 2026-11-14 | 70 | publish-after-scrub | أداة نظام نشطة 2026-11-14 | استخدام يومي محتمل |
| `sumatrapdf` | 2026-11-16 | 77,110 | archive | مصدر مُنزّل 77MB بلا وصف | بناء محلي؟ الأصل العام متاح — أرشفة مرشحة |
| `sync-github` | 2026-11-14 | 27 | publish-after-scrub | مغلب محتمل بـrepo-sync-toolkit | هل ما زال مستخدمًا محليًا؟ |
| `wine-ai-adaptive` | 2026-11-20 | 609 | publish-after-scrub | مشروع نشط 2026-11-20 | هل يستمر؟ |



## أصول HuggingFace (خطة §8.2)

| النوع | المعرّف | التنزيلات | الوسم | الإجراء |
|---|---|---|---|---|
| dataset | `DrAbdulmalek/arabic-medical-ocr-corrections` | 28 | keep-private | URGENT: تحويله gated فورًا — مطابق لـocr-core#76 (OCR-04) وهو اليوم عام بـ28 تنزيلًا |
| dataset | `DrAbdulmalek/arabic-bilingual-medical-glossary` | 87 | publish-after-scrub | يتبع مصير arabic-medical-glossary (scrub ثم عام) |
| dataset | `DrAbdulmalek/arabic-dictionaries-master` | 22 | publish-after-scrub | يتبع OMD-01: HF Bucket هو المرجع الوحيد بعد إزالة 1GB من git |
| dataset | `DrAbdulmalek/Translated_Books` | 19 | keep-private | قرار مالك: بيانات ترجمة شخصية — keep-private افتراضيًا |
| model | `DrAbdulmalek/qwen2.5-7b-abliterated` | 18 | keep-private | قرار مالك: نموذج abliterated — keep-private افتراضيًا |
| space | `DrAbdulmalek/handwriting-ocr` | — | publish-after-scrub | يتبع مصير arabic-handwriting-ocr-toolkit |
| space | `DrAbdulmalek/medical-ocr-trainer` | — | archive | يتبع مصير medical-ocr-trainer (مرشح أرشفة) |
| space | `DrAbdulmalek/medical-ocr-demo` | — | publish-after-scrub | يتبع قرار medical-ocr-demo (review) |
| space | `DrAbdulmalek/omni-medical-ocr` | — | publish-after-scrub | يتبع مصير omni-medical-suite (OMS-01) |

**عاجل:** `arabic-medical-ocr-corrections` عام اليوم بـ28 تنزيلًا — تحويله **gated** فورًا (يتطابق حرفيًا مع ocr-core#76 / OCR-04).

## سياسة الرموز (خطة §8.3)

- **قاعدة**: رمز Write واحد لكل غرض + إلغاء فوري بعد الاستخدام — إدارتها عبر `token-manager.py` الموجود في هذا المستودع (يخزّن في `~/.config/git-sync-system/secrets.env` بصلاحيات 600).
- **إجراء فوري معلق على المالك**: توكن 2026-11-25 المؤقت (نشر حزمة الإشوهات + دفع بوابة العقد) **انتهى غرضه ويجب إبطاله الآن** — لديه push/admin على المستودعات.
- سجل الرموز يُحدَّث هنا بعد كل استخدام (اسم الغرض، تاريخ الإنشاء، تاريخ الإبطال).

## سجل قرارات المالك (يُوثق هنا قبل أي أرشفة)

| التاريخ | القائمة المعتمدة للأرشفة | البصمة (أرقام manifest) | التوقيع/المرجع |
|---|---|---|---|
| — | — | — | — |

## معايير قبول issue #15 مقابل هذا الملف

- [x] «جرد آلي: آخر commit + آخر استهلاك فعلي» — الجدولان أعلاه (push + دليل استهلاك لكل مستودع)
- [x] «manifest.json واحد لكل الأصول» — `manifest.json` (45 مستودعًا + 9 أصول HF) في جذر هذا المستودع بوصفه وحدة الجرد المشتركة
- [x] «تصنيف كل أصل بثلاث وسوم» — عمود `privacy_tag` لكل أصل (keep-private / publish-after-scrub / archive)
- [x] «سياسة الرموز» — القسم أعلاه + الإجراء الفوري
- [ ] «تنفيذ GitHub Archive» — **متعمد التأجيل**: شرط الإشوه هو توثيق قرار المالك أولًا؛ الأداة جاهزة (`archive_repos.py`)
- [x] «تقرير الجرد منشور» — هذا الملف + تعليق على الإشوه #15
