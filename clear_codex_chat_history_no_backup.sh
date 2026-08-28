#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [ ! -d "$CODEX_HOME" ]; then
  echo "Codex home not found: $CODEX_HOME" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found. Please install sqlite3 first." >&2
  exit 1
fi

echo "=== Clearing local Codex chat history ==="
echo "Target: $CODEX_HOME"
echo
echo "建议先退出 Codex 再运行，否则当前活跃会话可能会被重新写入。"
echo

read -r -p "确定要清除所有 Codex 本地聊天记录吗？此操作不可逆 (y/N): " -n 1
echo

if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
  echo "操作已取消。"
  exit 0
fi

clear_sqlite_tables() {
  local database="$1"
  shift
  local table sql="PRAGMA foreign_keys = OFF;"

  [ -f "$database" ] || return 0

  for table in "$@"; do
    if [ "$(sqlite3 "$database" "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '$table';")" = "1" ]; then
      sql="$sql DELETE FROM \"$table\";"
    fi
  done

  sql="$sql PRAGMA wal_checkpoint(TRUNCATE); VACUUM;"
  sqlite3 "$database" "$sql" >/dev/null
}

# Table names vary between Codex releases, so only delete tables present locally.
clear_sqlite_tables "$CODEX_HOME/logs_2.sqlite" logs
clear_sqlite_tables "$CODEX_HOME/state_5.sqlite" \
  thread_spawn_edges thread_dynamic_tools agent_job_items agent_jobs threads thread_sections backfill_state
clear_sqlite_tables "$CODEX_HOME/goals_1.sqlite" thread_goals thread_goal_continuation_deferrals
clear_sqlite_tables "$CODEX_HOME/thread_history_1.sqlite" \
  thread_items thread_turns thread_history_projection_state
clear_sqlite_tables "$CODEX_HOME/queue_1.sqlite" queued_items queued_thread_revisions
clear_sqlite_tables "$CODEX_HOME/sqlite/codex-dev.db" \
  local_thread_catalog thread_timeline_ledger inbox_items automation_runs

if [ -f "$CODEX_HOME/session_index.jsonl" ]; then
  : > "$CODEX_HOME/session_index.jsonl"
fi

if [ -d "$CODEX_HOME/sessions" ]; then
  find "$CODEX_HOME/sessions" -type f -delete
fi

if [ -d "$CODEX_HOME/shell_snapshots" ]; then
  find "$CODEX_HOME/shell_snapshots" -type f -delete
fi

echo "Done. Local Codex chat history has been cleared."
