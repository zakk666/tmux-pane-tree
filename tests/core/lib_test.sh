#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

unset TMUX_SIDEBAR_STATE_DIR
unset XDG_STATE_HOME

fake_tmux_no_sidebar
fake_tmux_register_pane "%20" "work" "@1" "editor" "bash" "bash" "0" "/work/proj-a"
fake_tmux_register_pane "%21" "work" "@1" "editor" "bash" "bash" "0" "/work/proj-b"
printf '%%21\n' > "$TEST_TMUX_DATA_DIR/current_pane.txt"

export TMUX_PANE="%21"
output="$(bash scripts/core/lib.sh resolve_agent_target_pane "%20" 2>&1 || true)"
assert_eq "$output" "%20"

output="$(bash scripts/core/lib.sh resolve_agent_target_pane "" 2>&1 || true)"
assert_eq "$output" "%21"

unset TMUX_PANE
output="$(bash scripts/core/lib.sh resolve_agent_target_pane "" "/missing" "/work/proj-b" 2>&1 || true)"
assert_eq "$output" "%21"

output="$(bash scripts/core/lib.sh resolve_agent_target_pane "" "/no-match" 2>&1 || true)"
assert_eq "$output" ""
run_script scripts/core/lib.sh print_state_dir
assert_eq "$output" "$HOME/.local/state/tmux-sidebar"

export XDG_STATE_HOME="/tmp/xdg-state-test"
run_script scripts/core/lib.sh print_state_dir
assert_eq "$output" "/tmp/xdg-state-test/tmux-sidebar"
unset XDG_STATE_HOME
