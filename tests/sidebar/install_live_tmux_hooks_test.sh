#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/../testlib.sh"

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
HOME_DIR="$TEST_TMP/home"
PLUGIN_DST="$HOME_DIR/.config/tmux/plugins/tmux-sidebar"
TMUX_CONF="$HOME_DIR/.config/tmux/tmux.conf"
CLAUDE_SETTINGS="$HOME_DIR/.claude/settings.json"
CODEX_CONFIG="$HOME_DIR/.codex/config.toml"

fake_tmux_no_sidebar

mkdir -p "$(dirname "$TMUX_CONF")" "$(dirname "$CLAUDE_SETTINGS")" "$(dirname "$CODEX_CONFIG")"

cat > "$TMUX_CONF" <<'EOF'
run '~/.config/tmux/plugins/tpm/tpm'
EOF

cat > "$CLAUDE_SETTINGS" <<'EOF'
{}
EOF

cat > "$CODEX_CONFIG" <<'EOF'
model = "gpt-5"
EOF

tmux set-hook -gw 'window-pane-changed[201]' "run-shell -b '$HOME_DIR/.config/tmux/plugins/tmux-sidebar/scripts/on-pane-focus.sh #{pane_id} #{window_id}'"
tmux set-hook -gw 'window-layout-changed[209]' "run-shell -b $HOME_DIR/.config/tmux/plugins/tmux-sidebar/scripts/notify-sidebar.sh"
tmux set-hook -gw 'window-renamed[210]' "run-shell -b $HOME_DIR/.config/tmux/plugins/tmux-sidebar/scripts/notify-sidebar.sh"

TMUX="fake-session" \
HOME="$HOME_DIR" \
PLUGIN_SRC="$REPO_ROOT" \
PLUGIN_DST="$PLUGIN_DST" \
TMUX_CONF="$TMUX_CONF" \
CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
CODEX_CONFIG="$CODEX_CONFIG" \
TIMESTAMP="20260320000000" \
bash "$REPO_ROOT/scripts/install-live.sh"

window_hooks="$(tmux show-hooks -gw)"
assert_not_contains "$window_hooks" 'scripts/on-pane-focus.sh'
assert_not_contains "$window_hooks" 'scripts/notify-sidebar.sh'
