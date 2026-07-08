---
name: using-presenterm
description: Use when creating, editing, or presenting terminal slideshows with presenterm — markdown-based presentations rendered in the terminal, including slides with code execution, column layouts, images, themes, speaker notes, or PDF/HTML export.
---

# Using presenterm

## House Style (default for new decks)

Unless the user asks otherwise, every new deck follows this standard:

1. **Front matter title slide** — always start with:

```yaml
---
title: "Deck Title"
sub_title: one-line hook
author: Calum
theme:
  name: blackout
options:
  implicit_slide_ends: true
  incremental_lists: true
---
```

2. **Setext slide titles, no `end_slide`** — `implicit_slide_ends` means a new `Title` + `===` starts the next slide. Don't sprinkle `<!-- end_slide -->`.
3. **Section dividers** — each major section opens with a divider slide:

```markdown
<!-- jump_to_middle -->

Section Name
===

<!-- end_slide -->
```

(divider slides are the one place `end_slide` is still needed — no following title ends them if next slide is title-less)

4. **Code blocks always get `+line_numbers`.**
5. **Bullets are incremental by default** — write dense slides knowing they reveal stepwise; use `<!-- incremental_lists: false -->` locally for reference lists that should appear at once.
6. **Theme `blackout`** — custom true-black theme; source of truth is `dotfiles/presenterm/themes/blackout.yaml`, symlinked into presenterm's themes dir where any `.yaml` auto-loads as a named theme. That dir is `$XDG_CONFIG_HOME/presenterm/themes` if the env var is set, else the platform config dir — on macOS `~/Library/Application Support/presenterm/themes/`, NOT `~/.config`. A "theme does not exist" error usually means the symlink is in the wrong dir. Edit the dotfiles copy, never a local copy; if the symlink is missing on a machine, recreate it rather than switching themes.

## Overview

presenterm renders markdown files as terminal slideshows. A presentation is a single `.md` file: optional YAML front matter, then slides separated by `<!-- end_slide -->`. Features beyond plain markdown are driven by HTML comment commands and code-block attributes.

Run: `presenterm deck.md` (hot-reloads on save, jumps to edited slide). Use `presenterm --present deck.md` for the real talk (disables hot reload).

## Minimal Working Deck

```markdown
---
title: "My **talk**"
sub_title: shipping things
author: Calum
theme:
  name: catppuccin-mocha
---

First topic
===

Some content.

<!-- pause -->

More content after a keypress.

<!-- end_slide -->

Second topic
===

- point one
- point two
```

Front matter creates a title slide. Use `authors: [a, b]` for multiple authors. Setext headers (`Title` + `===`) become styled slide titles.

## Comment Commands (quick reference)

| Command | Effect |
|---|---|
| `<!-- end_slide -->` | end current slide |
| `<!-- pause -->` | stop rendering until keypress |
| `<!-- jump_to_middle -->` | vertically center what follows (section-divider slides) |
| `<!-- new_line -->` / `<!-- new_lines: 3 -->` | explicit vertical space (markdown collapses blank lines) |
| `<!-- alignment: left\|center\|right -->` | text alignment for rest of slide |
| `<!-- font_size: 2 -->` | scale text 1–7 (kitty ≥0.40 only) |
| `<!-- incremental_lists: true -->` | bullets appear one per keypress (until set false) |
| `<!-- list_item_newlines: 2 -->` | spacing between list items |
| `<!-- skip_slide -->` | omit slide from presentation |
| `<!-- no_footer -->` | drop footer on this slide |
| `<!-- include: other.md -->` | embed external markdown (paths relative to included file) |
| `<!-- speaker_note: text -->` | presenter-only note (multi-line: YAML `speaker_note: \|` block) |
| `<!-- // free-form comment -->` | ignored, safe for notes |

## Column Layouts

```markdown
<!-- column_layout: [2, 1] -->

<!-- column: 0 -->
Left content (2/3 width).

<!-- column: 1 -->
Right content (1/3 width).

<!-- reset_layout -->
Full-width again.
```

Numbers are proportional units. Centering trick: `[1, 3, 1]` and write only into column 1.

## Code Blocks

Attributes go after the language: ` ```rust +line_numbers {1,3|5-7} `

- `{1,3,5-7}` — highlight those lines only
- `{1,3|5-7|all}` — dynamic: each `|` group is a step, advance moves highlight
- `+line_numbers`, `+no_background`
- `+exec` — runnable with `ctrl+e` (requires launching with `-x`); output stateful across slide changes
- `+exec_replace` — auto-run, block replaced by output (requires `-X` opt-in)
- `+auto_exec`, `+acquire_terminal` (give program the TTY), `+pty` / `+pty:cols:rows` (for `top`-style tools)
- `+id:foo` + later `<!-- snippet_output: foo -->` — place output elsewhere (only on later slides)
- `+expect:failure` — snippet must exit non-zero
- Hidden-but-executed lines: prefix `///` (`#` in Rust)
- Validate all executable snippets: `presenterm --validate-snippets deck.md`

External file snippet:

````markdown
```file +exec +line_numbers
path: snippet.rs
language: rust
start_line: 5
end_line: 10
```
````

Mermaid / LaTeX / typst / D2 blocks render as images with `+render` (needs the respective tool installed); or set `options.auto_render_languages: [mermaid]`.

## Images

`![](img/diagram.png)` — paths relative to the presentation file. Size: `![image:width:50%](img.png)` (aspect ratio preserved). Needs kitty/iterm2/sixel-capable terminal (kitty, iterm2, WezTerm, ghostty, foot); ASCII-block fallback elsewhere. Remote URLs not supported. In tmux, enable `allow-passthrough`.

## Themes

Built-ins: `dark`, `light`, `terminal-dark`, `terminal-light`, `gruvbox-dark`, `catppuccin-{latte,frappe,macchiato,mocha}`, `tokyonight-{day,moon,night,storm}`.

```yaml
theme:
  name: dark            # or path: /abs/theme.yaml
  # or auto light/dark: {light: light, dark: dark}
  override:
    default:
      colors:
        foreground: "beeeff"
```

Also `--theme <name>` on CLI. Custom themes: drop `.yaml` files in presenterm's themes dir — `$XDG_CONFIG_HOME/presenterm/themes` if set, else platform config dir (macOS: `~/Library/Application Support/presenterm/themes/`, Linux: `~/.config/presenterm/themes/`). File name = theme name.

## Front Matter Options

```yaml
options:
  implicit_slide_ends: true      # new slide title ends previous slide — no end_slide needed
  end_slide_shorthand: true      # bare `---` ends a slide
  h1_slide_titles: true          # first `#` in slide becomes slide title
  incremental_lists: true        # all lists incremental by default
  command_prefix: "cmd:"         # only <!-- cmd:pause --> is a command
  image_attributes_prefix: ""    # ![width:50%](...) instead of image:width
  list_item_newlines: 2
  strict_front_matter_parsing: false   # tolerate unknown front-matter keys
  auto_render_languages: [mermaid]
```

`implicit_slide_ends: true` + setext titles gives the cleanest authoring style — prefer it for new decks.

## Export & Speaker Notes

- PDF: `presenterm --export-pdf deck.md` (needs `weasyprint`; or `uv run --with weasyprint presenterm --export-pdf deck.md`)
- HTML: `presenterm --export-html deck.md` (self-contained, no deps)
- Custom output path: `--output out.pdf`
- Speaker notes: presenter runs `presenterm deck.md --publish-speaker-notes`, second terminal runs `presenterm deck.md --listen-speaker-notes` (localhost UDP; macOS: one listener max). Config `speaker_notes.always_publish: true` removes need for the publish flag.

## Navigation (presenting)

Arrows/`hjkl`/PgUp-PgDn move; `gg` first, `G` last, `<n>G` jump; `ctrl+p` slide index; `?` key bindings; `ctrl+c` exit.

## Common Mistakes

- **Executable code does nothing** — you launched without `-x` (or `-X` for `exec_replace`). Execution is off by default.
- **Blank lines don't add space** — markdown collapses them; use `<!-- new_lines: N -->`.
- **Images broken** — terminal lacks a graphics protocol, or path isn't relative to the `.md` file, or remote URL (unsupported).
- **`snippet_output` fails** — reference must appear on a slide *after* the snippet.
- **Stray HTML comments error out** — presenterm parses all comments as commands; use `<!-- // ... -->` or set `command_prefix`.
- **Mixing `---` separators and front matter** — `---` only ends slides with `end_slide_shorthand: true`; otherwise it renders as a thematic break.
