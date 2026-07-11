#!/bin/bash
# simple-sync.sh — Zero-config batch sync (sync-github compatible mode)
# Usage: ./sync-scripts/simple-sync.sh [DIRECTORY]
# If no directory given, uses $HOME/GitHub or $GITHUB_DIR
#
# This is the --simple mode ported from the sync-github repo.
# Scans a directory for all git repos and syncs them with pull --ff-only.

DIR="${1:-${GITHUB_DIR:-$HOME/GitHub}}"

if [ ! -d "$DIR" ]; then
  echo "Error: Directory $DIR does not exist"
  exit 1
fi

echo "Simple Sync: $DIR"
echo "================================"
total=0; ok=0; fail=0

for d in "$DIR"/*/; do
  [ ! -d "$d/.git" ] && continue
  total=$((total + 1))
  name=$(basename "$d")
  branch=$(git -C "$d" branch --show-current 2>/dev/null)

  # If branch is master but GitHub uses main
  if [ "$branch" = "master" ] && git -C "$d" rev-parse --verify origin/main &>/dev/null; then
    git -C "$d" branch -M main
    branch="main"
  fi

  # Determine remote branch
  remote_branch="main"
  git -C "$d" rev-parse --verify "origin/$branch" &>/dev/null && remote_branch="$branch"

  # Set upstream if not set
  if ! git -C "$d" config "branch.$branch.remote" &>/dev/null; then
    git -C "$d" branch --set-upstream-to="origin/$remote_branch" "$branch" 2>/dev/null
  fi

  # Sync with ff-only, fallback to reset --hard
  if ! git -C "$d" pull --ff-only 2>/dev/null; then
    git -C "$d" reset --hard "origin/$remote_branch" 2>/dev/null
    git -C "$d" pull --ff-only 2>/dev/null
  fi

  if [ $? -eq 0 ]; then
    echo "  OK   $name"
    ok=$((ok + 1))
  else
    echo "  FAIL $name"
    fail=$((fail + 1))
  fi
done

echo "================================"
echo "OK: $ok | FAIL: $fail | TOTAL: $total"
