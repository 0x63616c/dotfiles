import { join } from "node:path";
import palette from "../palette/palette.json";

// 50 punchy string-color candidates, anchored on Blackout's existing jewel tones
// (accent/kw/str/fn/type/num/error) and their harmonious neighbors. Grouped by family.
const stringGroups: { group: string; colors: string[] }[] = [
  { group: "Greens", colors: ["#46d889", "#3ddc84", "#5ce68f", "#6ee7a0", "#34d399", "#2fbf71", "#7be08a", "#9be870"] },
  { group: "Teal / Aqua", colors: ["#2dd4bf", "#14e0c8", "#3edcd0", "#5ce0d8", "#00d9c0", "#4fd6c0"] },
  { group: "Cyan", colors: ["#57cdef", "#38bdf8", "#22d3ee", "#5cd6ff", "#7fdcf5", "#18c5e8"] },
  { group: "Blue", colors: ["#0a84ff", "#3b9bff", "#4d9fff", "#6f9bff", "#5a8dff"] },
  { group: "Violet / Purple", colors: ["#9a86ff", "#b07cff", "#a78bfa", "#8b7dff", "#c08cff", "#7c6cff"] },
  { group: "Pink / Magenta", colors: ["#f47ea0", "#ff7eb6", "#ff6ac1", "#f06595", "#ff85c0", "#e879f9"] },
  { group: "Red / Coral", colors: ["#fb5a4b", "#ff7a6e", "#ff6b6b", "#ff8a5c"] },
  { group: "Orange / Amber", colors: ["#ffb454", "#ffc679", "#ff9f45", "#ffa94d", "#ffcb6b"] },
  { group: "Yellow / Lime", colors: ["#ffe66d", "#e0d96b", "#b5e853", "#c3e88d"] },
];

const t = (cls: string, text: string) => `<span class="${cls}">${text}</span>`;

// A realistic TS/React-ish sample, heavy on strings so the change is obvious.
const code = `${t("c", "// blackout — syntax preview")}
${t("k", "import")} { ${t("v", "useState")}, ${t("v", "useEffect")} } ${t("k", "from")} ${t("s", '"react"')}${t("p", ";")}
${t("k", "import")} { ${t("ty", "Theme")} } ${t("k", "from")} ${t("s", '"./theme"')}${t("p", ";")}

${t("k", "const")} ${t("v", "PALETTE")} ${t("p", "=")} {
  ${t("v", "name")}${t("p", ":")} ${t("s", '"Blackout"')}${t("p", ",")}
  ${t("v", "accent")}${t("p", ":")} ${t("s", '"#0a84ff"')}${t("p", ",")}
  ${t("v", "version")}${t("p", ":")} ${t("n", "2")}${t("p", ",")}
  ${t("v", "enabled")}${t("p", ":")} ${t("n", "true")}${t("p", ",")}
}${t("p", ";")}

${t("c", "/** Greets a user by name. */")}
${t("k", "export function")} ${t("fn", "greet")}${t("p", "(")}${t("v", "name")}${t("p", ":")} ${t("ty", "string")}${t("p", ")")}${t("p", ":")} ${t("ty", "string")} {
  ${t("k", "const")} ${t("v", "msg")} ${t("p", "=")} ${t("s", "`Hello, ${name}! Welcome to ")}${t("s", "Blackout`")}${t("p", ";")}
  ${t("fn", "console")}${t("p", ".")}${t("fn", "log")}${t("p", "(")}${t("s", '"rendering:"')}${t("p", ",")} ${t("v", "msg")}${t("p", ")")}${t("p", ";")}
  ${t("k", "return")} ${t("v", "msg")}${t("p", ".")}${t("fn", "trim")}${t("p", "()")}${t("p", ";")}
}

${t("k", "const")} ${t("v", "files")} ${t("p", "=")} ${t("p", "[")}${t("s", '"index.ts"')}${t("p", ",")} ${t("s", '"theme.ts"')}${t("p", ",")} ${t("s", '"palette.json"')}${t("p", "]")}${t("p", ";")}`;

const swatches = stringGroups
  .map(
    (g) => `
    <div class="group-label">${g.group}</div>
    <div class="grid">${g.colors
      .map(
        (hex) => `<button class="tile" data-hex="${hex}" title="${hex}">
        <span class="chip" style="background:${hex}"></span>
        <span class="hex">${hex}</span>
      </button>`
      )
      .join("")}</div>`
  )
  .join("");

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Blackout — string color preview</title>
<style>
  :root {
    --bg: ${palette.bg};
    --currentLine: ${palette.currentLine};
    --border: ${palette.border};
    --fg: ${palette.fg};
    --fgMuted: ${palette.fgMuted};
    --lineNr: ${palette.lineNr};
    --accent: ${palette.accent};
    --kw: ${palette.kw};
    --fn: ${palette.fn};
    --type: ${palette.type};
    --num: ${palette.num};
    --comment: ${palette.comment};
    --punct: ${palette.punct};
    --var: ${palette.var};
    --str: ${palette.str};
  }
  * { box-sizing: border-box; }
  html { color-scheme: dark; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font: 13px/1.7 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    display: grid;
    grid-template-columns: 1fr 360px;
    min-height: 100vh;
  }
  ::-webkit-scrollbar { width: 10px; height: 10px; }
  ::-webkit-scrollbar-thumb { background: #ffffff1a; border-radius: 6px; }
  ::-webkit-scrollbar-thumb:hover { background: #ffffff2a; }
  ::-webkit-scrollbar-track { background: var(--bg); }

  .editor { padding: 0; overflow: auto; }
  .tabbar {
    display: flex; align-items: center; gap: 0;
    background: var(--bg); border-bottom: 1px solid var(--border);
    height: 36px; padding: 0 8px;
  }
  .tab {
    padding: 0 16px; height: 36px; display: flex; align-items: center;
    color: var(--fg); border-top: 2px solid var(--accent);
    font-size: 12px;
  }
  .tab .mod { color: var(--accent); margin-left: 8px; }
  .code-wrap { display: flex; }
  .gutter {
    text-align: right; color: var(--lineNr); user-select: none;
    padding: 18px 12px 18px 18px; white-space: pre;
  }
  pre {
    margin: 0; padding: 18px 24px 18px 0; white-space: pre;
    tab-size: 2;
  }
  .k  { color: var(--kw); }
  .s  { color: var(--str); }
  .fn { color: var(--fn); }
  .ty { color: var(--type); }
  .n  { color: var(--num); }
  .c  { color: var(--comment); font-style: italic; }
  .p  { color: var(--punct); }
  .v  { color: var(--var); }

  .panel {
    background: var(--bg); border-left: 1px solid var(--border);
    padding: 20px; font-family: ui-sans-serif, -apple-system, system-ui, sans-serif;
    position: sticky; top: 0; align-self: start; height: 100vh; overflow: auto;
  }
  .panel h1 { font-size: 13px; font-weight: 600; margin: 0 0 4px; letter-spacing: .02em; }
  .panel p.sub { font-size: 11px; color: var(--fgMuted); margin: 0 0 20px; line-height: 1.5; }
  .panel h2 { font-size: 11px; font-weight: 600; color: var(--fgMuted);
    text-transform: uppercase; letter-spacing: .08em; margin: 0 0 10px; }
  .swatches { margin-bottom: 24px; }
  .group-label { font-size: 10px; font-weight: 600; color: var(--fgMuted);
    text-transform: uppercase; letter-spacing: .08em; margin: 14px 0 8px; }
  .group-label:first-child { margin-top: 0; }
  .grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; }
  .tile {
    display: flex; align-items: center; gap: 9px;
    background: transparent; border: 1px solid var(--border); border-radius: 8px;
    padding: 7px 9px; cursor: pointer; color: var(--fg); text-align: left;
    font: inherit; transition: background .12s, border-color .12s;
  }
  .tile:hover { background: var(--currentLine); }
  .tile.active { border-color: var(--accent); background: var(--currentLine); }
  .tile .chip { width: 16px; height: 16px; border-radius: 5px; flex: 0 0 auto;
    box-shadow: 0 0 0 1px #ffffff14 inset; }
  .tile .hex { color: var(--fgMuted); font-family: ui-monospace, monospace; font-size: 11px; }
  .custom { display: flex; align-items: center; gap: 10px; margin-bottom: 18px; }
  .custom input[type=color] {
    width: 36px; height: 36px; padding: 0; border: 1px solid var(--border);
    border-radius: 8px; background: var(--bg); cursor: pointer;
  }
  .custom input[type=text] {
    flex: 1; background: var(--bg); border: 1px solid var(--border);
    border-radius: 8px; color: var(--fg); padding: 9px 11px;
    font: inherit; font-family: ui-monospace, monospace; font-size: 12px;
  }
  .apply-note {
    font-size: 11px; color: var(--fgMuted); line-height: 1.6;
    border-top: 1px solid var(--border); padding-top: 16px;
  }
  .apply-note code { color: var(--fg); background: var(--currentLine);
    padding: 1px 5px; border-radius: 4px; }
  .current-hex { color: var(--str); font-family: ui-monospace, monospace; }
</style>
</head>
<body>
  <div class="editor">
    <div class="tabbar">
      <div class="tab">theme.ts<span class="mod">●</span></div>
    </div>
    <div class="code-wrap">
      <div class="gutter" id="gutter"></div>
      <pre id="code">${code}</pre>
    </div>
  </div>

  <aside class="panel">
    <h1>String color</h1>
    <p class="sub">Live preview. Click any tile or pick a custom color — every string in the sample updates instantly. Current: <span class="current-hex" id="currentHex">${palette.str}</span></p>

    <h2>50 punchy options</h2>
    <div class="swatches">${swatches}</div>

    <h2>Custom</h2>
    <div class="custom">
      <input type="color" id="picker" value="${palette.str}" />
      <input type="text" id="hexInput" value="${palette.str}" spellcheck="false" />
    </div>

    <div class="apply-note">
      To keep a color: set <code>"str"</code> in <code>palette/palette.json</code> to the hex you like, then run <code>bun run build</code>.
    </div>
  </aside>

<script>
  const root = document.documentElement;
  const currentHex = document.getElementById("currentHex");
  const picker = document.getElementById("picker");
  const hexInput = document.getElementById("hexInput");
  const swatches = [...document.querySelectorAll(".tile")];

  function setStr(hex) {
    hex = hex.trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return;
    root.style.setProperty("--str", hex);
    currentHex.textContent = hex;
    picker.value = hex;
    hexInput.value = hex;
    swatches.forEach(s => s.classList.toggle("active", s.dataset.hex.toLowerCase() === hex.toLowerCase()));
  }

  swatches.forEach(s => s.addEventListener("click", () => setStr(s.dataset.hex)));
  picker.addEventListener("input", e => setStr(e.target.value));
  hexInput.addEventListener("input", e => setStr(e.target.value));

  // build gutter line numbers
  const lines = document.getElementById("code").textContent.split("\\n").length;
  document.getElementById("gutter").textContent =
    Array.from({length: lines}, (_, i) => i + 1).join("\\n");

  setStr("${palette.str}");
</script>
</body>
</html>`;

await Bun.write(join(import.meta.dir, "../preview.html"), html);
console.log("Wrote preview.html");
