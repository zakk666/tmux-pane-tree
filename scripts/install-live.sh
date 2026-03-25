#!/usr/bin/env bash
set -euo pipefail

PLUGIN_SRC="${PLUGIN_SRC:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
PLUGIN_DST="${PLUGIN_DST:-$HOME/.config/tmux/plugins/tmux-sidebar}"
TMUX_CONF="${TMUX_CONF:-$HOME/.config/tmux/tmux.conf}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
CURSOR_HOOKS="${CURSOR_HOOKS:-$HOME/.cursor/hooks.json}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d%H%M%S)}"

mkdir -p "$(dirname "$PLUGIN_DST")"
rm -rf "$PLUGIN_DST"
mkdir -p "$PLUGIN_DST"
cp -R "$PLUGIN_SRC"/. "$PLUGIN_DST"/
chmod +x "$PLUGIN_DST"/sidebar.tmux "$PLUGIN_DST"/examples/*.sh
find "$PLUGIN_DST/scripts" -type f -name '*.sh' -exec chmod +x {} +

cp "$TMUX_CONF" "$TMUX_CONF.bak-tmux-sidebar-$TIMESTAMP"
python3 - <<'PY'
from pathlib import Path

path = Path.home() / ".config/tmux/tmux.conf"
plugin_dir = "~/.config/tmux/plugins/tmux-sidebar"
abs_plugin_dir = str(Path.home() / ".config/tmux/plugins/tmux-sidebar")
line = f"source-file {abs_plugin_dir}/sidebar.conf"
stale_patterns = [
    f'if-shell "test -f {plugin_dir}/sidebar.tmux" "source-file {plugin_dir}/sidebar.tmux"',
    f"source-file {plugin_dir}/sidebar.tmux",
    f"source-file {abs_plugin_dir}/sidebar.tmux",
    f"run-shell '{plugin_dir}/sidebar.tmux'",
    f"run-shell '{abs_plugin_dir}/sidebar.tmux'",
    f'if-shell "test -f {plugin_dir}/sidebar.conf" "source-file {plugin_dir}/sidebar.conf"',
    f"source-file {plugin_dir}/sidebar.conf",
    f"source-file {abs_plugin_dir}/sidebar.conf",
    f"run-shell '{plugin_dir}/sidebar.conf'",
    f"run-shell '{abs_plugin_dir}/sidebar.conf'",
]
text = path.read_text()
for pat in stale_patterns:
    text = text.replace(pat + "\n", "")
    text = text.replace("\n" + pat, "")
tpm_line = "run '~/.config/tmux/plugins/tpm/tpm'"
if tpm_line in text:
    text = text.replace(tpm_line, f"{tpm_line}\n{line}", 1)
else:
    text = text.rstrip() + "\n" + line + "\n"
path.write_text(text)
PY

CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
CODEX_CONFIG="$CODEX_CONFIG" \
CURSOR_HOOKS="$CURSOR_HOOKS" \
TIMESTAMP="$TIMESTAMP" \
bash "$PLUGIN_DST/scripts/features/hooks/install-agent-hooks.sh"

if [ -n "${TMUX:-}" ]; then
  tmux show-hooks -g 2>/dev/null \
    | awk '/tmux-sidebar/ {print $1}' \
    | while IFS= read -r hook_name; do
        [ -n "$hook_name" ] || continue
        tmux set-hook -gu "$hook_name" || true
      done
  tmux show-hooks -gw 2>/dev/null \
    | awk '/tmux-sidebar/ {print $1}' \
    | while IFS= read -r hook_name; do
        [ -n "$hook_name" ] || continue
        tmux set-hook -guw "$hook_name" || true
      done
  tmux show-hooks -gp 2>/dev/null \
    | awk '/tmux-sidebar/ {print $1}' \
    | while IFS= read -r hook_name; do
        [ -n "$hook_name" ] || continue
        tmux set-hook -gup "$hook_name" || true
      done
  tmux source-file "$TMUX_CONF" || true
  bash "$PLUGIN_DST/scripts/features/sidebar/reload-sidebar-panes.sh" || true
fi
