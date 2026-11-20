#!/bin/sh
# SessionStart hook (shared plugin): one line telling Claude which profile this session runs on. Its stdout becomes
# session context. Same rule as the status line: a profile only when CLAUDE_CONFIG_DIR is exactly ~/.claude-NAME.
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cfg="${cfg%/}"
profile=''
case "$cfg" in "$HOME"/.claude-*) profile="${cfg#"$HOME"/.claude-}"; case "$profile" in */*) profile='' ;; esac ;; esac
skill='To change Claude Code config for any profile (settings, plugins, mods, skills, hooks, MCP servers, status line), load the claude-profiles skill first.'
case "$profile" in
  personal) printf 'Claude profile: personal (~/.claude-personal, personal login). %s\n' "$skill" ;;
  vov) printf 'Claude profile: vov (~/.claude-vov, work login). %s\n' "$skill" ;;
  ?*) printf 'Claude profile: %s (~/.claude-%s, not one of the known profiles). %s\n' "$profile" "$profile" "$skill" ;;
  *)
    shown="$(printf '%s' "$cfg" | sed "s#^$HOME/#~/#")"
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then state="set to $shown"; else state='unset'; fi
    printf 'Claude profile: none (CLAUDE_CONFIG_DIR is %s). This session reads %s, not a profile dir: if that is ~/.claude it shows personal'"'"'s files through a link, but with the default login and ~/.claude.json. Mention this to Calum if it matters for the task. %s\n' \
      "$state" "$shown" "$skill"
    ;;
esac
