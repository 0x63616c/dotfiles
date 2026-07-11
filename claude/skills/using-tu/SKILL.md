---
name: using-tu
description: Always use when running or testing an interactive CLI/TUI during development or operations — driving htop/vim/ncurses-style apps, testing tools we build (e.g. tools/glance), capturing terminal screenshots, or sending keystrokes/mouse input to a program that needs a real terminal.
---

# Using tu (terminal-use)

## Overview

`tu` runs programs in a headless virtual terminal: spawn, read the screen, send keys, drive the mouse. Use it whenever a program needs a real TTY — piping stdin/stdout into TUIs does not work.

Full command reference: `tu usage`. Everything below is the working subset.

## Core loop

```bash
tu run --name myapp ./myapp arg1      # spawn (default 120x40, TERM=xterm-256color)
tu wait --name myapp --stable 500     # wait for screen to settle (or --text "regex")
tu screenshot --name myapp            # read screen as text
tu press --name myapp Down Down Enter # interact
tu screenshot --name myapp --png      # PNG render (prints temp path; -o file.png for explicit)
tu kill --name myapp                  # cleanup when done
```

Every command takes `--name <s>` to pick a session (default: `"default"`). Use a distinct name per app; `tu list` shows active sessions, `tu status` shows pid/alive/exit code.

## Quick reference

| Task | Command |
|---|---|
| Spawn with shell/env/size | `tu run --shell --env K=V --size 160x50 --cwd <dir> <cmd>` |
| Wait for output | `tu wait --text "Complete" --timeout 10000` |
| Wait for screen idle | `tu wait --stable 500` |
| Read screen | `tu screenshot` (text) / `tu screenshot --png --output file.png` (omit `--output` for auto temp path) |
| Scrollback | `tu scrollback --lines 100` |
| Type literal text | `tu type "hello"` |
| Keys | `tu press Ctrl+C` / `tu press Escape : w q Enter` / `tu press F2 Shift+Tab` |
| Paste (bracketed) | `tu paste "<text>"` |
| Click by label | `tu mouse click --on-text "OK"` (`--clicks 2` double, `--on-regex`, `--match-index N`) |
| Click by coords | `tu mouse click <col> <row>` (0-based) |
| Scroll | `tu mouse scroll down --amount 5` |
| Resize | `tu resize 160x50` |
| Machine output | append `--json` (auto when stdout not a TTY) |

## Gotchas

- **Always `tu wait` before screenshotting** after spawn or input — apps redraw asynchronously; `--stable 500` is a good default.
- **Check `tu mouse state` before clicking** — if app hasn't enabled mouse mode, clicks error out (`--force` sends bytes anyway).
- **Kill sessions when done** (`tu kill --name <s>`) — they persist otherwise.
- Text screenshots append a `△ tu mouse cursor at (col,row)` trailer line; PNG renders cursor as magenta △.
- Full-screen TUIs usually have empty scrollback — read via `screenshot`, not `scrollback`.

## When NOT to use

Plain non-interactive commands (build, test, grep) — use normal shell; tu adds overhead with no benefit.
