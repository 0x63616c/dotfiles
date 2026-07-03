# themes

Custom themes for Cursor, VS Code, and OpenCode.

## Structure

```
cursor/         → Cursor & VS Code themes (package.json, install script, build pipeline)
opencode/       → OpenCode desktop and TUI theme files
antinote/       → Antinote (notes app) theme files
```

## Cursor / VS Code — Blackout

A true-black, shadow-free dark theme for Cursor & VS Code. Hand-picked syntax colors, a Vercel-blue accent, and subtle bracket-pair colors. Designed for [Geist Mono](https://vercel.com/font), but works with any font.

### Install

```bash
cd cursor
./scripts/install.sh
```

Then reload the window and pick **Blackout** from the theme picker (`Cmd+K Cmd+T`). The installer links into Cursor and VS Code if it finds them.

### Font (optional)

The theme is tuned for Geist Mono with ligatures. Install [Geist Mono](https://vercel.com/font), then add to your settings (or copy from `settings.recommended.json`):

```json
"editor.fontFamily": "Geist Mono, ui-monospace, monospace",
"editor.fontLigatures": true
```

### Tweak the colors

Every color comes from one file: `palette/palette.json`. Edit it, rebuild, reload.

```bash
cd cursor
bun run build
```

## OpenCode — Blackout (TUI)

A true-black TUI theme for OpenCode. Loaded via the global Opencode plugin config.

## OpenCode — Lucent Orng++ (TUI)

Opaque-solid variant of the built-in `lucent-orng` theme, with transparent surfaces removed.

| File | Purpose |
|---|---|
| `package.json` | Opencode plugin manifest that exposes the custom themes |
| `lucent-orng.json` | Reference copy of the built-in theme |
| `lucent-orng-plusplus.json` | TUI variant with opaque surfaces |

Global config:
```json
{
  "theme": "lucent-orng-plusplus",
  "plugin": ["/Users/calum/code/github.com/0x63616c/themes"]
}
```

## Antinote — Blackout

A true-black theme for [Antinote](https://antinote.io). Same Blackout palette as the editor themes.

| File | Purpose |
|---|---|
| `blackout.json` | The Blackout theme |
| `example.json` | Stock theme schema, kept as a field reference |
| `sync.sh` | Copies themes into the Antinote container |

Antinote is sandboxed and won't follow symlinks out of its container, so themes are **copied**, not linked:

```bash
cd antinote
./sync.sh
```

Then reload the theme in Antinote. Edit `blackout.json`, re-run `sync.sh`, reload.

## License

MIT
