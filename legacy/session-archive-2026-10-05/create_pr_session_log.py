#!/usr/bin/env python3
"""Create draft PR #16: session forensic log (docs/session-log-20261005 -> main)."""
import json
import urllib.request

TOKEN = open("/home/z/my-project/.secrets/gh_token").read().strip()

BODY = """## 🎯 الهدف

تنفيذ أمر المالك: «احفظ كل خطوة مجراة في GitHub» + «راجع المحادثات في هذه الجلسة من أولها لمعرفة ما تم عمله وضاع لاحقًا».

هذا PR **توثيق خالص** (ملف واحد، +82 سطرًا): `docs/SESSION-LOG-2026-10-05.md`.

## 📄 ما يحويه السجل

1. **الخط الزمني للجلسة من أولها** بثلاث مراحل:
   - (أ) قبل نفاد السياق [معاد البناء من الملخص]: تعريف مهمة OCR، دراسة docs/09، PR #14
   - (ب) أوامر المالك نصًا + الردّان الخارجيان (حزمة «خيار هـ» + حزمة ABBYY clean-room بـ 9 أقسام)
   - (ج) التنفيذ الفعلي بالشواهد: أمن التوكن، الجردة، matching_view.py، PR #15، CI أخضر
2. **جدول مصير كل عنصر** بتحقق حي من GitHub API: PRs #13/#14/#15، الحملة التيليجرامية (tg-campaign-toolkit)، **الواجهة (channel-ops-dashboard — محفوظة بل أوسع من المحلي)**، الأرشيف
3. **دفتر الفقد الموثق**: RESET #2/#5/#6/#7/#9 — ما ضاع نهائيًا (stashes/M001/سجلات) وما استُعيد ولماذا
4. **القرارات المعلقة على المالك** وحدود التوثيق

## 🔑 خلاصة تصحيحية

«صفحات تيليجرام الطبية» و«تعديل الواجهة» محفوظتان على GitHub فعلاً (tg-campaign-toolkit + channel-ops-dashboard)؛ المفقود فعليًا: المعاينات الجارية (تموت بنهاية الجلسة) + تعديلات ما بعد 2026-09-30 غير المدفوعة (مساحة العمل الجذرية بلا remote — موثق في §3).

## ✅ قائمة التحقق

- [x] ملف واحد توثيقي، بلا أي كود أو تبعيات
- [x] فحص أسرار: نظيف (لا توكنات/مفاتيح)
- [x] كل الروابط والأرقام حيّة وقت الكتابة (2026-10-05)
- [ ] CI أخضر
- [ ] قرار الدمج للمالك

## 🔗 مرتبط

- PR #15 (الكود المرفق لهذه الجلسة + جردة الحزمة الخارجية)
- التحديث المصاحب في `workspace-scripts-archive` (سكربتات الجلسة + أرشيف worklog)
"""

req = urllib.request.Request(
    "https://api.github.com/repos/DrAbdulmalek/ocr-core/pulls",
    data=json.dumps(
        {
            "title": "docs(session): سجل الجلسة الجنائي 2026-10-05 — الخط الزمني + مصير كل عنصر + دفتر الفقد",
            "head": "docs/session-log-20261005",
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
print("head:", d["head"]["sha"][:7], "| base:", d["base"]["ref"])
