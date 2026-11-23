#!/usr/bin/env bash
# 10_inventory.sh — جرد حي: المستودعات + الـPRs المفتوحة (قراءة فقط)
set -euo pipefail
source ./lib.sh
require_gh
mkdir -p inventory
gh api "users/$OWNER/repos?per_page=100&sort=updated" --paginate > inventory/repos.json
python3 - <<'EOF'
import json, subprocess, os
repos = json.load(open("inventory/repos.json"))
out = []
for r in repos:
    name = r["name"]
    p = subprocess.run(["gh","api",f"repos/{r['owner']['login']}/{name}/pulls?state=open&per_page=100"],
                       capture_output=True, text=True)
    prs = json.loads(p.stdout) if p.returncode == 0 else []
    out.append({"name": name, "fork": r["fork"], "archived": r["archived"],
                "license": (r.get("license") or {}).get("spdx_id"),
                "open_prs": [{"n": p["number"], "title": p["title"], "draft": p["draft"],
                              "head": p["head"]["ref"], "created": p["created_at"]} for p in prs]})
json.dump(out, open("inventory/live_inventory.json","w"), ensure_ascii=False, indent=1)
print(f"repos={len(out)} open_prs={sum(len(r['open_prs']) for r in out)}")
EOF
log "الجرد الحي جاهز: inventory/live_inventory.json"
