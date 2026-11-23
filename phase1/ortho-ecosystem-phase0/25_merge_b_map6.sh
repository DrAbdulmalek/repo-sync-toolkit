#!/usr/bin/env bash
# 25_merge_b_map6.sh — الفئة ب: IFM#78 ثم PRs الخارطة الستة + بنود التكامل الفوري
set -euo pipefail
source ./lib.sh
require_gh

# 1) IFM#78: مدموج مسبقًا في main (90b38f0، CI 4/4) بتاريخ 2026-11-23 بتوكيل المالك — تخطٍ موثق
log "=== الفئة ب-1: intelli-file-manager#78 — مدموج مسبقًا (90b38f0) — تخطٍ"

# 2) الخارطة الستة
MAP6=(
  "intelli-file-manager 80"
  "OmniFile_Processor 4"
  "ocr-core 71"
  "scanner-fixer 6"
  "repo-sync-toolkit 12"
  "medical-ocr-benchmarks 1"
)
for entry in "${MAP6[@]}"; do
  set -- $entry; repo=$1; pr=$2
  log "=== الفئة ب-2: $repo#$pr"
  head=$(gh pr view --repo "$OWNER/$repo" "$pr" --json headRefName --jq .headRefName)
  merge_pr "$repo" "$pr" "$head" merge || log "توقف $repo#$pr"
done

# 3) بنود التكامل الفوري بعد الدمج (من نص البرومبت) — تُطبق كـPRs صغيرة
log "=== بنود التكامل الفوري (تذكير تنفيذي):"
log "  a) سطر gate_text_for_indexing(text, source=str(path)) في RAGEngine.ingest_file — intelli-file-manager/src/core/rag_engine.py"
log "  b) ربط merge_into_gate_report() في scripts/run_all_benchmarks.py — medical-ocr-benchmarks"
log "ملاحظة: البندان يُطبقان عبر فرع fix/integration-* وPR منفصل لكل منهما (قاعدة مسار PR الإلزامية)."
log "انتهت الفئة ب"
