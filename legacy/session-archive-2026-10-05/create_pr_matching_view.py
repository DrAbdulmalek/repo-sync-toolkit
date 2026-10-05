#!/usr/bin/env python3
"""Create draft PR for feat/matching-view-charter -> main (owner-authorized)."""
import json
import urllib.request

TOKEN = open("/home/z/my-project/.secrets/gh_token").read().strip()

BODY = """## 🎯 الهدف

تنفيذ طلب المالك «نفّذ وادفع حزمة تحسينات OCR المقترحة… وأضف ما يناسب منها» — **بأمانة هندسية**: الجردة أظهرت أن 7/8 عناصر مقترحة خارجيًا موجودة في المستودع بنسخ أقوى أو معيبة، فلم يُدفع أي منها كما هو؛ واعتُمدت الفكرة الوحيدة ذات القيمة غير المغطاة وأُعيد تنفيذها بفعالية.

## 📦 المكوّنات (3 ملفات، +388 سطرًا)

### 1. `src/ocr_core/postprocess/matching_view.py`
- **عقد غير تدميري** وفق ميثاق الدليل البصري: `original_text` يُحفظ حرفيًا بايت-ببايت + نسخة «مطابقة» منفصلة + سجل تدقيق لكل قاعدة (`MatchingChange`: الاسم/العدد/الملاحظة).
- **حماية طبية فعلية** لا شكلية: كل «رقم + وحدة» (mg/ml/°C/%/ملغ/مل/جم…، أرقام غربية أو عربية-هندية) يُقنَّع قبل القواعد ويُستعاد حرفيًا — `٥٠٠ ملغ` و`٣٧.٥ °C` لا تمسّها قواعد التطبيع.
- **توحيد ة→ه اختياري** احترامًا لتحذير انحياز المقاييس الموثق في `normalization.arabic_strong_normalize`.
- أصناف محارف متوافقة مع `normalization.py` لاتساق نتائج المطابقة مع خط الأنابيب الرئيسي.
- صفر تبعيات جديدة (`re`/`unicodedata`/`dataclasses`).

### 2. `tests/test_matching_view.py` — 21 اختبارًا
العقد غير التدميري، كل قاعدة بعدّها، الحماية الطبية (قناع/استعادة/تعطيل)، التاء الاختيارية، الانعدامية (idempotency)، سجل التغييرات.

### 3. `docs/enhancement-package-audit.md` — الجردة التنفيذية
جدول 8 عناصر مقترحة خارجيًا مع الحكم والدليل، وعيوب محددة كانت ستُدفع لولا الفحص:
- **WER معطوب رياضيًا** (مسافة أحرف على كلمات مدموجة ÷ عدد كلمات المرجع) مقابل `metrics.py::wer` الصحيح (S+D+I على مستوى الكلمات).
- **حماية طبية ميتة**: النمط يُحسب ولا يُستخدم — التوحيد يطبق على الجرعات رغم الادعاء.
- **استدعاء API غير موجود** (`adapter.extract`) مقابل بروتوكول `process_image -> OCRResult`.
- استبدال EnsembleEngine المركّب بنسخة أبسط + قيمة افتراضية قابلة للتحوير + محرك معلن لا يُحمَّل.

## 🧪 الاختبارات

```
pytest -q   # 256 passed محليًا (كان 235) — بلا انحدار
pytest -q tests/test_matching_view.py   # 21 passed
```

## 🧭 المنهجية

Clean Room: كل الكود أصلي من التعريفات العامة والملفات القائمة في هذا المستودع — دون نسخ أي تنفيذ خارجي. التوكن المستخدم للدفع محفوظ محليًا (600)، لم يُطبع، ونُظّف من remote URL بعد الدفع.

## 🚫 ما لا يفعله هذا PR

- لا يستبدل EnsembleEngine/metrics/normalization/r tl_utils بأي نسخة خارجية
- لا يضيف تبعيات، ولا يعدّل CI، ولا يدمج نفسه تلقائيًا

## ✅ قائمة التحقق

- [x] 3 ملفات مضافة فقط (+388)
- [x] `pytest -q` أخضر محليًا (256)
- [x] لا تبعيات جديدة في `pyproject.toml`
- [x] الجردة موثقة بالشواهد في `docs/enhancement-package-audit.md`
- [ ] CI أخضر
- [ ] قرار الدمج للمالك

## ⏭️ مؤجَّل بوعي (ليس مرفوضًا)

- إعادة التعرف الانتقائي للمناطق (regional): تحتاج مسودة تصميم على بروتوكول المحركات أولًا
- إشارة «يُراجَع بشريًا» عند تقارب ثقة المحركات: عبر `OCRResult.meta` في فرع لاحق
"""

req = urllib.request.Request(
    "https://api.github.com/repos/DrAbdulmalek/ocr-core/pulls",
    data=json.dumps(
        {
            "title": "feat(postprocess): عرض مطابقة غير تدميري بحماية طبية فعلية + جردة حزمة التحسينات المقترحة",
            "head": "feat/matching-view-charter",
            "base": "main",
            "draft": True,
            "body": BODY,
        }
    ).encode(),
    headers={
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": "ocr-core-session",
    },
    method="POST",
)
with urllib.request.urlopen(req) as resp:
    d = json.load(resp)
print("PR:", d["number"], "| state:", d["state"], "| draft:", d["draft"], "| url:", d["html_url"])
print("head:", d["head"]["sha"][:7], "| base:", d["base"]["ref"], "| mergeable_state:", d.get("mergeable_state"))
