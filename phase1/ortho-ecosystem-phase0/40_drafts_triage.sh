#!/usr/bin/env bash
# 40_drafts_triage.sh — الفئة د: تقرير قرار لكل مسودة + توحيد المكررات
# لا يدمج ولا يغلق شيئًا آليًا — يولد قرارات مقترحة للمراجعة ثم ينفذها عند DRY_RUN=0 بعد تعديل قائمة القرارات.
set -euo pipefail
source ./lib.sh
require_gh

python3 - <<'EOF'
import json
inv = json.load(open("inventory/live_inventory.json"))
harness, gdrive, other_drafts = [], [], []
for r in inv:
    for p in r["open_prs"]:
        if not p["draft"]: continue
        t = p["title"]
        if "Harness Engineering" in t: harness.append((r["name"], p["n"], t))
        elif "GDRIVE_POINTER" in t: gdrive.append((r["name"], p["n"], t))
        else: other_drafts.append((r["name"], p["n"], t))
print("=== مسودات Harness Engineering v2.0 (توحيد في PR مرجعي واحد — المقترح: ocr-core#10) ===")
for h in harness: print("  ", h)
print("=== GDRIVE_POINTER المتماثلتان (المقترح: glossary#4 مرجعي وإغلاق dictionaries#2) ===")
for g in gdrive: print("  ", g)
print("=== بقية المسودات: قرار لكل واحدة (إنهاء/دمج/إغلاق) ===")
for d in other_drafts: print("  ", d)
EOF
log "تقرير المسودات مطبوع أعلاه — عدّل قائمة القرارات ثم أعد التشغيل بـDRY_RUN=0 لإغلاق ما أُقر."
log "انتهت الفئة د (تقرير فقط في هذا التشغيل)"
