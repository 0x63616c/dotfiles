#!/usr/bin/env bash
# Tokyo Night statusline for Claude Code

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten model name: "Claude 3.5 Sonnet" -> "Sonnet", "Claude Opus 4.5" -> "Opus", etc.
short_model=$(echo "$model" | sed -E 's/^Claude //; s/ \(default\)//g; s/\(([0-9]+[KMG]) context\)/[\1]/g')

# Show only the directory name (basename of the current path)
short_cwd=$(basename "$cwd")

# Git branch (skip optional lock to avoid blocking)
branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)

# Tokyo Night ANSI colors (using 256-color approximations that map well)
# We use \e[38;2;R;G;Bm for true color
RESET='\e[0m'
DIM='\e[2m'

# Colors
PURPLE='\e[38;2;187;154;247m'   # #bb9af7 — model name
BLUE='\e[38;2;122;162;247m'     # #7aa2f7 — cwd
GREEN='\e[38;2;158;206;106m'    # #9ece6a — git branch
CYAN='\e[38;2;125;207;255m'     # #7dcfff — branch parens
FG='\e[38;2;169;177;214m'       # #a9b1d6 — separators / $
YELLOW='\e[38;2;224;175;104m'   # #e0af68 — context %
RED='\e[38;2;247;118;142m'      # #f7768e — context % when high (>80)
ORANGE='\e[38;2;255;158;100m'   # #ff9e64 — xhigh effort
BRIGHT='\e[38;2;192;202;245m'   # #c0caf5 — clock (brighter fg)

# Build context segment with color based on usage
ctx_segment=""
if [ -n "$used" ]; then
  used_int=${used%.*}
  used_int=${used_int:-0}
  if [ "$used_int" -ge 80 ]; then
    ctx_color="$RED"
  elif [ "$used_int" -ge 50 ]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$CYAN"
  fi
  ctx_segment=" ${FG}|${RESET} ${ctx_color}${used_int}%%${RESET}"
fi

# Check git dirty status
dirty=""
if [ -n "$cwd" ]; then
  porcelain=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null)
  [ -n "$porcelain" ] && dirty="*"
fi

# main vs origin/main: show origin/main's short SHA, and how many commits local
# main is AHEAD of it (unpushed) as (-N). ALWAYS main->origin/main regardless of
# the current branch/checkout — we only care about the main divergence. Non-
# blocking, no network (origin/main is the cached remote-tracking ref, updated
# on push/fetch).
main_sha=""
main_ahead=""
main_age=""
if [ -n "$cwd" ]; then
  main_sha=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short origin/main 2>/dev/null)
  if [ -n "$main_sha" ]; then
    n=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-list --count origin/main..main 2>/dev/null)
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
      main_ahead="$n"
      # Age of origin/main's tip commit: time elapsed from its commit time to now.
      ct=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" log -1 --format=%ct origin/main 2>/dev/null)
      if [ -n "$ct" ]; then
        diff=$(( $(date +%s) - ct ))
        [ "$diff" -lt 0 ] && diff=0
        if [ "$diff" -lt 3600 ]; then
          main_age="$(( diff / 60 ))m"
        elif [ "$diff" -lt 86400 ]; then
          main_age="$(( diff / 3600 ))h"
        else
          main_age="$(( diff / 86400 ))d"
        fi
      fi
    fi
  fi
fi

# Make the cwd name an OSC 8 hyperlink to the GitHub remote. Ghostty (and most
# modern terminals) render ESC]8;;<url>ST <text> ESC]8;;ST as just <text>,
# clickable + underlined, URL hidden. Keeps the blue cwd color.
# Normalize git@github.com:owner/repo.git and ssh:// forms to a clean https URL.
cwd_display="$short_cwd"
if [ -n "$cwd" ]; then
  origin=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" remote get-url origin 2>/dev/null)
  if [ -n "$origin" ]; then
    repo_path=$(echo "$origin" | sed -E 's#^git@[^:]+:#https://github.com/#; s#^ssh://git@([^/]+)/#https://\1/#; s#\.git$##')
    OSC_OPEN='\e]8;;'"${repo_path}"'\e\\'
    OSC_CLOSE='\e]8;;\e\\'
    cwd_display="${OSC_OPEN}${short_cwd}${OSC_CLOSE}"
  fi
fi

# Build effort segment — wrapped in parens, all gray
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
effort_segment=""
if [ -n "$effort_level" ]; then
  effort_segment=" ${FG}(${effort_level})${RESET}"
fi

# Build branch segment
branch_segment=""
if [ -n "$branch" ]; then
  branch_segment=" ${CYAN}(${RESET}${GREEN}${branch}${RESET}"
  [ -n "$dirty" ] && branch_segment="${branch_segment}${YELLOW}*${RESET}"
  branch_segment="${branch_segment}${CYAN})${RESET}"
fi

# Build origin/main SHA segment, with (-N) when local main is ahead (unpushed)
sha_segment=""
if [ -n "$main_sha" ]; then
  sha_segment=" ${FG}|${RESET} ${ORANGE}${main_sha}${RESET}"
  if [ -n "$main_ahead" ]; then
    sha_segment="${sha_segment}${FG}(${RESET}${YELLOW}-${main_ahead}${RESET}"
    [ -n "$main_age" ] && sha_segment="${sha_segment}${FG}, ${RESET}${YELLOW}${main_age}${RESET}"
    sha_segment="${sha_segment}${FG})${RESET}"
  fi
fi

# Clock segment for the far left, e.g. [4:57pm]
clock=$(date +"%-I:%M%p" | tr '[:upper:]' '[:lower:]')
clock_segment="${FG}[${RESET}${BRIGHT}${clock}${RESET}${FG}]${RESET} "

printf "${clock_segment}${PURPLE}${short_model}${RESET}${effort_segment} ${FG}|${RESET} ${BLUE}${cwd_display}${RESET}${branch_segment}${sha_segment}${ctx_segment}\n"
