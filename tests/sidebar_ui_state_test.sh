#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

fake_tmux_set_tree <<'EOF'
work|@1|editor|%1|nvim|shell|0
work|@1|editor|%2|claude|claude|1
work|@1|editor|%99|python3|tmux-sidebar|0
ops|@3|logs|%9|tail|tail|0
solo|@5|sidebar-only|%77|python3|tmux-sidebar|0
EOF

output="$(python3 scripts/sidebar-ui.py --dump-render 2>&1)"

case "$output" in
  *'invalid option:'* ) fail "sidebar UI should not leak tmux stderr for missing options" ;;
esac

fake_tmux_register_main_pane "%9"

output="$(python3 scripts/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" '├─ work'
assert_contains "$output" '│     └─ %2 claude'
assert_contains "$output" '▶ │     └─ %9 tail'
case "$output" in
  *'%99 tmux-sidebar'* ) fail "sidebar pane should be hidden when window has other panes" ;;
esac
assert_contains "$output" '└─ solo'
assert_contains "$output" '%77 python3'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%2|superlongpanecommand|superlongpanecommand|1
EOF
printf '14\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_width.txt"

output="$(python3 scripts/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" '…'
case "$output" in
  *'superlongpanecommand'* ) fail "sidebar UI should truncate long rows for narrow widths" ;;
esac
