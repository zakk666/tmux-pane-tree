#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/hook-lib.sh"
update_helper="${TMUX_SIDEBAR_UPDATE_HELPER:-$SCRIPT_DIR/update-pane-state.sh}"
forward_notify="${TMUX_SIDEBAR_CODEX_NOTIFY_FORWARD:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/peon-ping/adapters/codex.sh}"

resolve_hook_input "${1:-}" "${2:-}"

if [ -x "$forward_notify" ]; then
  printf '%s' "$hook_payload" | "$forward_notify" "$hook_event" || true
fi

parse_hook_result codex "$hook_event"
[ -n "$hook_status" ] || exit 0

exec "$update_helper" \
  --pane "${TMUX_PANE:-}" \
  --app codex \
  --status "$hook_status" \
  --message "$hook_message"
