#!/bin/bash
# sync-github.sh — مزامنة كل المستودعات في ~/GitHub مع GitHub
# الاستخدام: bash ~/GitHub/sync-github.sh

GITHUB_DIR="$HOME/GitHub"

if [ ! -d "$GITHUB_DIR" ]; then
  echo "❌ المجلد $GITHUB_DIR غير موجود"
  exit 1
fi

echo "🔄 جاري مزامنة المستودعات..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
total=0; ok=0; fail=0

for d in "$GITHUB_DIR"/*/; do
  [ ! -d "$d/.git" ] && continue
  total=$((total + 1))
  name=$(basename "$d")
  branch=$(git -C "$d" branch --show-current 2>/dev/null)

  # إذا كان الفرع master و GitHub يستخدم main
  if [ "$branch" = "master" ] && git -C "$d" rev-parse --verify origin/main &>/dev/null; then
    git -C "$d" branch -M main
    branch="main"
  fi

  # تحديد الفرع البعيد (main أو الفرع الحالي)
  remote_branch="main"
  git -C "$d" rev-parse --verify "origin/$branch" &>/dev/null && remote_branch="$branch"

  # ربط الفرع إذا لم يكن مربوطاً
  if ! git -C "$d" config "branch.$branch.remote" &>/dev/null; then
    git -C "$d" branch --set-upstream-to="origin/$remote_branch" "$branch" 2>/dev/null
  fi

  # إذا كان هناك تباعد بين الفرعين، أعد التعيين
  if ! git -C "$d" pull --ff-only 2>/dev/null; then
    git -C "$d" reset --hard "origin/$remote_branch" 2>/dev/null
    git -C "$d" pull --ff-only 2>/dev/null
  fi

  if [ $? -eq 0 ]; then
    echo "✅ $name"
    ok=$((ok + 1))
  else
    echo "❌ $name"
    fail=$((fail + 1))
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ نجح: $ok | ❌ فشل: $fail | 📦 المجموع: $total"
