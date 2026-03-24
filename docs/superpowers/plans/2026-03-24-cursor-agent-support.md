# Cursor Agent Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class `cursor` agent support to the sidebar with the same install flow, hook wiring, badge states, examples, filter behavior, and docs coverage that `claude`, `codex`, and `opencode` already have.

**Architecture:** Add a native Cursor hook integration at `~/.cursor/hooks.json`, a dedicated `hook-cursor.sh` wrapper, and a `parse_cursor()` branch in `scripts/core/hook-parser.py`. Install the Cursor hook with the same absolute `PLUGIN_DST/.../hook-cursor.sh` path strategy already used for Claude, because user-level Cursor hooks run from `~/.cursor/`, not from the plugin directory. Bind Cursor events to tmux panes by preferring `TMUX_PANE` and falling back to matching `workspace_roots` against tmux pane working directories; because Cursor does not expose Claude-style `Notification` / `PermissionRequest` events, treat `postToolUseFailure` with `failure_type=permission_denied` as the best available `needs-input` signal and allow active `cursor` state to relabel a generic shell pane while that state is non-idle.

**Tech Stack:** Bash hook wrappers, Python hook parsing, Python curses sidebar UI, tmux options/state files

---

### Task 1: Lock pane binding and Cursor event mapping in tests

**Files:**
- Modify: `tests/testlib.sh`
- Modify: `tests/core/lib_test.sh`
- Modify: `tests/hooks/hook_scripts_test.sh`
- Test: `tests/core/lib_test.sh`
- Test: `tests/hooks/hook_scripts_test.sh`

- [ ] **Step 1: Extend fake tmux with pane working-directory support**

Update `tests/testlib.sh` so fake panes can carry a `pane_current_path` value and fake tmux can answer `#{pane_current_path}` lookups plus any `list-panes` format needed by the new resolver helper.

- [ ] **Step 2: Write the failing pane-resolution test**

Add coverage in `tests/core/lib_test.sh` for:
- explicit pane ids winning over everything else
- `TMUX_PANE` being used when it points at a live pane
- Cursor fallback walking `workspace_roots` in order and selecting the first root that resolves to a tmux pane current path when `TMUX_PANE` is missing
- no match returning an empty pane id instead of writing stale state

- [ ] **Step 3: Write the failing Cursor hook-status tests**

Add coverage in `tests/hooks/hook_scripts_test.sh` for these real Cursor-style stdin payloads:
- `sessionStart` -> `idle`
- `sessionEnd` -> `idle`
- `beforeSubmitPrompt` -> `running`
- `subagentStart` -> `running`
- `stop` with `status=completed` -> `done`
- `stop` with `status=aborted` -> `idle`
- `stop` with `status=error` -> `error`
- `postToolUseFailure` with `failure_type=permission_denied` -> `needs-input`
- `postToolUseFailure` with `failure_type=timeout` -> `error`
- `postToolUseFailure` with any other failure type -> `error`

Pass the event name through `hook_event_name` in JSON even when no argv event is provided, so the tests match how Cursor actually invokes hooks.

- [ ] **Step 4: Run the focused tests to confirm they fail**

Run:
- `bash tests/core/lib_test.sh`
- `bash tests/hooks/hook_scripts_test.sh`

Expected:
- `tests/core/lib_test.sh` fails because there is no pane resolver for Cursor workspace roots yet
- `tests/hooks/hook_scripts_test.sh` fails because `hook-cursor.sh` and `parse_cursor()` do not exist yet

- [ ] **Step 5: Commit the red tests**

```bash
git add tests/testlib.sh tests/core/lib_test.sh tests/hooks/hook_scripts_test.sh docs/superpowers/plans/2026-03-24-cursor-agent-support.md
git commit -m "test: define cursor hook behavior"
```

### Task 2: Add Cursor pane resolution and hook parsing

**Files:**
- Modify: `scripts/core/lib.sh`
- Modify: `scripts/core/hook-lib.sh`
- Modify: `scripts/core/hook-parser.py`
- Create: `scripts/features/hooks/hook-cursor.sh`
- Test: `tests/core/lib_test.sh`
- Test: `tests/hooks/hook_scripts_test.sh`

- [ ] **Step 1: Implement pane resolution in shared bash helpers**

Add a helper in `scripts/core/lib.sh` that resolves the target pane by:
- using an explicit `--pane` / provided pane id first
- then `TMUX_PANE` if it is present and live
- then the first Cursor workspace root that resolves to a tmux pane current path
- otherwise returning an empty string so the hook exits cleanly

Keep the path match deterministic: walk `workspace_roots` in order, prefer exact matches first, then the active pane among exact matches, then longest-prefix matches, then the lowest numeric pane id as a final tie-break. Never guess across unrelated panes.

- [ ] **Step 2: Teach the hook library to extract Cursor workspace roots**

Update `scripts/core/hook-lib.sh` so `hook-cursor.sh` can read the normalized event name plus the first `workspace_roots` entry from the JSON payload without duplicating JSON-parsing shell code in every wrapper.

- [ ] **Step 3: Implement Cursor status parsing**

Add `parse_cursor(event, payload)` to `scripts/core/hook-parser.py` and include `cursor` in the CLI choices. Derive the logical event from the first non-empty value among the argv event, `hook_event_name`, `event`, and `type` fields. Use this mapping:
- `sessionstart`, `sessionend` -> `idle`
- `beforesubmitprompt`, `pretooluse`, `posttooluse`, `subagentstart`, `afteragentthought`, `afteragentresponse` -> `running`
- `posttoolusefailure` + `permission_denied` -> `needs-input`
- `posttoolusefailure` + other failure types -> `error`
- `stop` + `completed` -> `done`
- `stop` + `error` -> `error`
- `stop` + `aborted` -> `idle`
- anything else -> empty status so noisy events are ignored

Do not register or map `subagentStop`: rely on the top-level `stop` hook to mark completion so subagent shutdown does not incorrectly flip an in-progress parent run to `done`.

- [ ] **Step 4: Add the Cursor hook wrapper**

Create `scripts/features/hooks/hook-cursor.sh` mirroring the existing wrappers:
- resolve stdin/argv payload through `hook-lib.sh`
- normalize the event name from the payload
- resolve the pane via the new shared helper
- call `parse_hook_result cursor "$hook_event"`
- exit early when no pane or no status is available
- write state with `--app cursor`

- [ ] **Step 5: Run the focused tests and make them pass**

Run:
- `bash tests/core/lib_test.sh`
- `bash tests/hooks/hook_scripts_test.sh`

Expected: PASS

- [ ] **Step 6: Commit the hook implementation**

```bash
git add scripts/core/lib.sh scripts/core/hook-lib.sh scripts/core/hook-parser.py scripts/features/hooks/hook-cursor.sh tests/testlib.sh tests/core/lib_test.sh tests/hooks/hook_scripts_test.sh
git commit -m "feat: add cursor hook parser"
```

### Task 3: Install Cursor hooks automatically

**Files:**
- Modify: `scripts/features/hooks/install-agent-hooks.sh`
- Modify: `scripts/install-live.sh`
- Modify: `tests/hooks/install_agent_hooks_test.sh`
- Modify: `tests/sidebar/install_live_test.sh`
- Test: `tests/hooks/install_agent_hooks_test.sh`
- Test: `tests/sidebar/install_live_test.sh`

- [ ] **Step 1: Write the failing installer assertions**

Update the installer tests so they expect:
- `~/.cursor/hooks.json` to be created or updated
- the installed config to reference the absolute installed `hook-cursor.sh` path under `PLUGIN_DST`
- the config to include the exact Cursor events used by the parser (`sessionStart`, `sessionEnd`, `beforeSubmitPrompt`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `subagentStart`, `afterAgentThought`, `afterAgentResponse`, `stop`)
- `scripts/install-live.sh` to pass any Cursor config path overrides through to `install-agent-hooks.sh`

- [ ] **Step 2: Run the installer tests to confirm they fail**

Run:
- `bash tests/hooks/install_agent_hooks_test.sh`
- `bash tests/sidebar/install_live_test.sh`

Expected: FAIL because no Cursor hook config is installed yet

- [ ] **Step 3: Patch `~/.cursor/hooks.json` idempotently**

Update `scripts/features/hooks/install-agent-hooks.sh` to:
- add `CURSOR_HOOKS="${CURSOR_HOOKS:-$HOME/.cursor/hooks.json}"`
- back up existing Cursor config with the same timestamped suffix pattern used elsewhere
- create a valid `{ "version": 1, "hooks": {} }` file when none exists
- emit native Cursor hook entries in the documented shape `{ "command": "/absolute/path/to/hook-cursor.sh", "timeout": 10 }`
- append the absolute installed `hook-cursor.sh` command once per target event without duplicating existing entries
- preserve unrelated Cursor hooks already present in the file

- [ ] **Step 4: Thread the new config path through live install**

Update `scripts/install-live.sh` so `CURSOR_HOOKS` is forwarded alongside `CLAUDE_SETTINGS` and `CODEX_CONFIG`.

- [ ] **Step 5: Run the installer tests and make them pass**

Run:
- `bash tests/hooks/install_agent_hooks_test.sh`
- `bash tests/sidebar/install_live_test.sh`

Expected: PASS

- [ ] **Step 6: Commit the installer work**

```bash
git add scripts/features/hooks/install-agent-hooks.sh scripts/install-live.sh tests/hooks/install_agent_hooks_test.sh tests/sidebar/install_live_test.sh
git commit -m "feat: install cursor hooks"
```

### Task 4: Teach the sidebar to recognize Cursor panes

**Files:**
- Modify: `scripts/ui/sidebar_ui_lib/status.py`
- Modify: `tests/ui/sidebar_ui_state_test.sh`
- Modify: `tests/ui/sidebar_ui_filter_option_test.sh`
- Test: `tests/ui/sidebar_ui_state_test.sh`
- Test: `tests/ui/sidebar_ui_filter_option_test.sh`

- [ ] **Step 1: Write the failing UI assertions**

Add coverage for:
- `cursor` state files rendering `cursor ⏳`, `cursor ❓`, `cursor ✅`, and `cursor ❌`
- window auto-renaming to `cursor` when the active pane is Cursor-driven
- filter matching via `cursor` token and `pane_state.app == "cursor"`
- shell panes with active Cursor state being relabeled to `cursor` while status is `running`, `needs-input`, `done`, or `error`
- the same shell panes reverting to their live shell label when status becomes `idle`

- [ ] **Step 2: Run the UI tests to confirm they fail**

Run:
- `bash tests/ui/sidebar_ui_state_test.sh`
- `bash tests/ui/sidebar_ui_filter_option_test.sh`

Expected: FAIL because `status.py` only knows about `claude`, `codex`, and `opencode`

- [ ] **Step 3: Implement Cursor detection and relabeling**

Update `scripts/ui/sidebar_ui_lib/status.py` to:
- add `looks_like_cursor()`
- include `cursor` anywhere the app whitelist currently hard-codes `claude`, `codex`, and `opencode`
- recognize `cursor` for live labels, state labels, auto window names, and filter token matching
- allow state-driven relabeling for `cursor` on generic shell panes only while the stored status is non-idle, since Cursor has no stable pane command/title signal comparable to `claude` semver titles or `codex` terminal output

- [ ] **Step 4: Run the UI tests and make them pass**

Run:
- `bash tests/ui/sidebar_ui_state_test.sh`
- `bash tests/ui/sidebar_ui_filter_option_test.sh`

Expected: PASS

- [ ] **Step 5: Commit the UI changes**

```bash
git add scripts/ui/sidebar_ui_lib/status.py tests/ui/sidebar_ui_state_test.sh tests/ui/sidebar_ui_filter_option_test.sh
git commit -m "feat: show cursor agent status"
```

### Task 5: Add Cursor examples and documentation

**Files:**
- Create: `examples/cursor-hook.sh`
- Modify: `README.md`
- Modify: `tests/examples/hook_examples_test.sh`
- Modify: `tests/examples/hook_examples_runtime_test.sh`
- Test: `tests/examples/hook_examples_test.sh`
- Test: `tests/examples/hook_examples_runtime_test.sh`

- [ ] **Step 1: Write the failing example/docs checks**

Extend the example tests so they expect:
- `examples/cursor-hook.sh` to exist and point at `scripts/features/hooks/hook-cursor.sh`
- `README.md` to mention `Cursor` anywhere it currently lists `Claude`, `Codex`, and `OpenCode`
- `README.md` to document `~/.cursor/hooks.json` in the installer and manual-wiring sections

- [ ] **Step 2: Run the example tests to confirm they fail**

Run:
- `bash tests/examples/hook_examples_test.sh`
- `bash tests/examples/hook_examples_runtime_test.sh`

Expected: FAIL because there is no Cursor example or README coverage yet

- [ ] **Step 3: Add the example wrapper**

Create `examples/cursor-hook.sh` in the same style as the other examples. Make it emit a compact JSON payload with:
- `hook_event_name`
- `workspace_roots`
- `status`
- `failure_type`
- `agent_message`

Use environment variables so the runtime test can simulate the important Cursor transitions without opening Cursor.

- [ ] **Step 4: Document the new support clearly**

Update `README.md` to:
- describe the sidebar as supporting `claude`, `codex`, `opencode`, and `cursor`
- add `~/.cursor/hooks.json` to the installer output list
- include `hook-cursor.sh` in manual wiring and examples
- update filter examples to include `cursor`
- note that the most reliable pane binding comes from launching Cursor from the tmux pane you want associated with the agent, with workspace-root matching as the fallback when `TMUX_PANE` is absent
- call out that `needs-input` is synthesized from Cursor’s `permission_denied` tool failures because Cursor does not expose Claude-style permission events

- [ ] **Step 5: Run the example tests and make them pass**

Run:
- `bash tests/examples/hook_examples_test.sh`
- `bash tests/examples/hook_examples_runtime_test.sh`

Expected: PASS

- [ ] **Step 6: Commit docs and examples**

```bash
git add examples/cursor-hook.sh README.md tests/examples/hook_examples_test.sh tests/examples/hook_examples_runtime_test.sh
git commit -m "docs: add cursor hook example"
```

### Task 6: Verify the full integration

**Files:**
- Verify only: `scripts/features/hooks/hook-cursor.sh`
- Verify only: `scripts/features/hooks/install-agent-hooks.sh`
- Verify only: `scripts/ui/sidebar_ui_lib/status.py`

- [ ] **Step 1: Run the full automated suite**

Run: `bash tests/run.sh`

Expected: PASS

- [ ] **Step 2: Install into the live plugin directory**

Run: `bash scripts/install-live.sh`

Expected: the plugin is copied into `~/.config/tmux/plugins/tmux-sidebar`, tmux config is re-sourced, and agent hook configs are rewritten for Claude, Codex, OpenCode, and Cursor

- [ ] **Step 3: Verify Cursor badge transitions in a live tmux session**

Manual check:
1. Start a fresh tmux test session.
2. Open or launch Cursor from the pane that should own the agent state.
3. Trigger a simple agent run in Cursor.
4. Confirm the sidebar shows `cursor ⏳` while the agent is working.
5. Confirm completion yields `cursor ✅`.
6. Force an agent failure and confirm `cursor ❌`.
7. If you can reproduce a permission-denied tool failure, confirm `cursor ❓`.
8. Focus the pane and confirm `done` / `needs-input` clear back to `idle`, matching existing sidebar behavior.

- [ ] **Step 4: Commit any verification-driven fixes**

```bash
git add .
git commit -m "fix: polish cursor sidebar integration"
```
