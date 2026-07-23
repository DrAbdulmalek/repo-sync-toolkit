#!/bin/bash
# =============================================
# lib-common.sh — مكتب

SYNC_DIR="${SYNC_DIR:-$HOME/github-sync-system}"
CONFIG_FILE="$SYNC_DIR/config/repos.txt"
SETTINGS_FILE="$SYNC_DIR/config/settings.env"
LOG_DIR="$SYNC_DIR/logs"
mkdir -p "$LOG_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'
