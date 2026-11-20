#!/bin/sh
# SessionStart hook (shared plugin): one line telling Claude which profile this session runs on. Its stdout becomes
# session context. The profile is the config dir's name after ".claude-", following links (~/.claude is a link to
# ~/.claude-personal for tools that don't set CLAUDE_CONFIG_DIR).
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
real="$(cd "$dir" 2>/dev/null && pwd -P)" || real="$dir"
name="${real##*/}"
case "$name" in
  .claude-*) profile="${name#.claude-}" ;;
  *) profile="unknown" ;;
esac
case "$profile" in
  vov) login="work login" ;;
  personal) login="personal login" ;;
  *) login="not a known profile" ;;
esac
shown="$(printf '%s' "$dir" | sed "s#^$HOME/#~/#")"
printf 'Claude profile: %s (%s, %s). To change Claude Code config for any profile (settings, plugins, mods, skills, hooks, MCP servers, status line), load the claude-profiles skill first.\n' \
  "$profile" "$shown" "$login"
