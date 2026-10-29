// AUTO-GENERATED from webapp/index.html by tools/embed_webapp.py — do not edit.
#pragma once
#include <pgmspace.h>
static const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Split-Flap Controller</title>
<style>
  :root {
    --bg: #0a0a0a;
    --panel: #141414;
    --panel-2: #1c1c1c;
    --line: #2a2a2a;
    --text: #f2f2f2;
    --muted: #8a8a8a;
    --accent: #0a84ff;
    --ok: #30d158;
    --warn: #ff9f0a;
    --err: #ff453a;
    --flap-bg: #111;
    --flap-text: #fafafa;
    --gap: 4px;
    font-synthesis: none;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; }
  body {
    background: var(--bg);
    color: var(--text);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    display: flex;
    flex-direction: column;
    min-height: 100%;
  }
  header {
    padding: 16px 20px;
    border-bottom: 1px solid var(--line);
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }
  header h1 { font-size: 16px; margin: 0; font-weight: 600; letter-spacing: .2px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--err); box-shadow: 0 0 8px currentColor; }
  .dot.ok { background: var(--ok); }
  .dot.connecting { background: var(--warn); }
  .spacer { flex: 1; }
  main { padding: 22px 20px; display: flex; flex-direction: column; gap: 22px; max-width: 1200px; width: 100%; margin: 0 auto; }

  /* Display board */
  .board-wrap { display: flex; justify-content: center; padding: 20px; background: #000; border: 1px solid var(--line); border-radius: 14px; overflow-x: auto; }
  .board { display: grid; gap: 10px 6px; }
  .row { display: grid; gap: var(--gap); grid-auto-flow: column; }
  .cell {
    position: relative;
    width: 40px; height: 56px;
    background: var(--flap-bg);
    border-radius: 4px;
    display: flex; align-items: center; justify-content: center;
    font-family: "SF Mono", "Cascadia Mono", ui-monospace, Menlo, Consolas, monospace;
    font-weight: 700;
    font-size: 30px;
    color: var(--flap-text);
    box-shadow: inset 0 0 0 1px #000, 0 1px 2px rgba(0,0,0,.6);
    overflow: hidden;
    user-select: none;
  }
  /* the split line across the middle of every flap */
  .cell::after {
    content: ""; position: absolute; left: 0; right: 0; top: 50%;
    height: 2px; transform: translateY(-1px);
    background: #000; opacity: .85; z-index: 3; pointer-events: none;
  }
  .cell.flip .glyph { animation: flip .18s ease-in; }
  @keyframes flip {
    0% { transform: translateY(-6%) scaleY(.86); opacity: .4; }
    100% { transform: none; opacity: 1; }
  }

  /* Controls */
  .grid2 { display: grid; grid-template-columns: 1fr; gap: 16px; }
  @media (min-width: 820px){ .grid2 { grid-template-columns: 1.4fr 1fr; } }
  .card { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px; }
  .card h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .1em; color: var(--muted); margin: 0 0 12px; font-weight: 600; }
  label { display: block; font-size: 12px; color: var(--muted); margin: 10px 0 4px; }
  input[type=text], input[type=number], textarea, select {
    width: 100%; background: var(--panel-2); color: var(--text);
    border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; font: inherit;
  }
  textarea { resize: vertical; min-height: 70px; font-family: ui-monospace, Menlo, monospace; text-transform: uppercase; letter-spacing: .12em; }
  .row-inline { display: flex; gap: 10px; }
  .row-inline > * { flex: 1; }
  .btn {
    appearance: none; border: 1px solid var(--line); background: var(--panel-2); color: var(--text);
    padding: 10px 16px; border-radius: 9px; font: inherit; font-weight: 600; cursor: pointer;
    transition: filter .12s, background .12s;
  }
  .btn:hover { filter: brightness(1.25); }
  .btn.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  .btn.ghost { background: transparent; }
  .btn-row { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 14px; }
  .hint { font-size: 12px; color: var(--muted); margin-top: 8px; }
  .invalid { color: var(--warn); }
  .kv { display: flex; justify-content: space-between; font-size: 13px; padding: 5px 0; border-bottom: 1px dashed var(--line); }
  .kv:last-child { border-bottom: 0; }
  .kv span:last-child { color: var(--muted); font-variant-numeric: tabular-nums; }
  code { background: var(--panel-2); padding: 1px 5px; border-radius: 4px; font-size: 12px; }
  .legend { font-size: 11px; color: var(--muted); margin-top: 10px; word-break: break-all; }
  footer { margin-top: auto; padding: 14px 20px; border-top: 1px solid var(--line); color: var(--muted); font-size: 12px; }
</style>
</head>
<body>
<header>
  <span class="dot" id="statusDot" title="disconnected"></span>
  <h1>Split-Flap Controller</h1>
  <span class="spacer"></span>
  <span class="hint" id="statusText">Offline — running in preview mode</span>
</header>

<main>
  <div class="board-wrap">
    <div class="board" id="board" aria-label="split-flap display"></div>
  </div>

  <div class="grid2">
    <div class="card">
      <h2>Message</h2>
      <textarea id="msg" placeholder="TYPE HERE…" spellcheck="false">HELLO WORLD</textarea>
      <div class="hint" id="charHint"></div>
      <div class="btn-row">
        <button class="btn primary" id="sendBtn">Send to display</button>
        <button class="btn" id="helloBtn">Hello World demo</button>
        <button class="btn ghost" id="clearBtn">Clear</button>
      </div>
      <div class="row-inline" style="margin-top:14px">
        <div>
          <label for="align">Alignment</label>
          <select id="align">
            <option value="left">Left</option>
            <option value="center" selected>Center</option>
            <option value="right">Right</option>
          </select>
        </div>
        <div>
          <label for="wrap">Multi-line</label>
          <select id="wrap">
            <option value="wrap" selected>Word-wrap across rows</option>
            <option value="rows">One line per row (use ↵)</option>
          </select>
        </div>
      </div>
    </div>

    <div class="card">
      <h2>Connection</h2>
      <label for="host">ESP32 host / IP</label>
      <input type="text" id="host" placeholder="splitflap.local  or  192.168.1.50" />
      <div class="row-inline" style="margin-top:6px">
        <div>
          <label for="rows">Rows</label>
          <input type="number" id="rows" min="1" max="16" value="4" />
        </div>
        <div>
          <label for="cols">Columns</label>
          <input type="number" id="cols" min="1" max="32" value="16" />
        </div>
      </div>
      <div class="btn-row">
        <button class="btn primary" id="connectBtn">Connect</button>
        <button class="btn ghost" id="applyGrid">Apply size</button>
      </div>
      <div style="margin-top:14px">
        <div class="kv"><span>Modules</span><span id="statModules">64</span></div>
        <div class="kv"><span>Homed</span><span id="statHomed">—</span></div>
        <div class="kv"><span>Moving</span><span id="statMoving">—</span></div>
        <div class="kv"><span>Firmware</span><span id="statFw">—</span></div>
      </div>
      <div class="legend" id="legend"></div>
    </div>
  </div>
</main>

<footer>
  Preview runs fully offline. Enter your ESP32 host and hit Connect to drive real hardware.
  API: <code>POST /api/text</code> · <code>GET /api/status</code> · <code>WS /ws</code>
</footer>

<script>
/* ------------------------------------------------------------------ *
 * Split-Flap Controller — single-file web app.
 * Works offline as a visual simulator; when a host is set it drives a
 * real ESP32 over the JSON HTTP API + a status WebSocket.
 * The character set below is the canonical order from
 * hardware/flaps/charset.json — keep the two in sync.
 * ------------------------------------------------------------------ */
const CHARSET = [
  " ",
  "A","B","C","D","E","F","G","H","I","J","K","L","M",
  "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
  "0","1","2","3","4","5","6","7","8","9",
  ".",",","!","?","-","/","&",
  "$","£","€","¥"
];
const CHARSET_SET = new Set(CHARSET);
const FLAP_COUNT = CHARSET.length;

const $ = (id) => document.getElementById(id);
const state = {
  rows: 4, cols: 16,
  host: "",
  ws: null,
  connected: false,
  cells: [],       // 2D array of DOM nodes
  shown: [],       // 2D array of currently-shown glyphs
};

/* ---------- persistence ---------- */
function saveCfg(){
  localStorage.setItem("sf_cfg", JSON.stringify({host: state.host, rows: state.rows, cols: state.cols}));
}
function loadCfg(){
  try {
    const c = JSON.parse(localStorage.getItem("sf_cfg") || "{}");
    if (c.host) { state.host = c.host; $("host").value = c.host; }
    if (c.rows) { state.rows = c.rows; $("rows").value = c.rows; }
    if (c.cols) { state.cols = c.cols; $("cols").value = c.cols; }
  } catch {}
}

/* ---------- board rendering ---------- */
function buildBoard(){
  const board = $("board");
  board.innerHTML = "";
  board.style.gridTemplateRows = `repeat(${state.rows}, auto)`;
  state.cells = [];
  state.shown = [];
  for (let r = 0; r < state.rows; r++){
    const rowEl = document.createElement("div");
    rowEl.className = "row";
    const rowCells = [];
    const rowShown = [];
    for (let c = 0; c < state.cols; c++){
      const cell = document.createElement("div");
      cell.className = "cell";
      const glyph = document.createElement("span");
      glyph.className = "glyph";
      glyph.textContent = " ";
      cell.appendChild(glyph);
      rowEl.appendChild(cell);
      rowCells.push(cell);
      rowShown.push(" ");
    }
    board.appendChild(rowEl);
    state.cells.push(rowCells);
    state.shown.push(rowShown);
  }
  $("statModules").textContent = state.rows * state.cols;
}

/* Animate a single cell stepping through flaps to the target glyph. */
function setCell(r, c, target){
  if (r >= state.rows || c >= state.cols) return;
  target = (target || " ").toUpperCase();
  if (!CHARSET_SET.has(target)) target = " ";
  const from = CHARSET.indexOf(state.shown[r][c]);
  const to = CHARSET.indexOf(target);
  if (from === to) return;
  const cell = state.cells[r][c];
  const glyph = cell.querySelector(".glyph");
  // number of flap steps forward (drum only turns one way)
  let steps = (to - from + FLAP_COUNT) % FLAP_COUNT;
  let i = 0, cur = from;
  const tick = () => {
    cur = (cur + 1) % FLAP_COUNT;
    glyph.textContent = CHARSET[cur];
    cell.classList.remove("flip"); void cell.offsetWidth; cell.classList.add("flip");
    i++;
    if (i < steps) setTimeout(tick, 22);
    else { cell.classList.remove("flip"); }
  };
  if (steps > 0) tick();
  state.shown[r][c] = target;
}

/* ---------- text layout ---------- */
function layout(text){
  const align = $("align").value;
  const mode = $("wrap").value;
  const grid = Array.from({length: state.rows}, () => Array(state.cols).fill(" "));
  let lines = [];
  const clean = text.toUpperCase();
  if (mode === "rows"){
    lines = clean.split(/\r?\n/);
  } else {
    // word-wrap into cols
    const words = clean.replace(/\r?\n/g, " ").split(/\s+/).filter(Boolean);
    let line = "";
    for (const w of words){
      if (!line.length) line = w.slice(0, state.cols);
      else if (line.length + 1 + w.length <= state.cols) line += " " + w;
      else { lines.push(line); line = w.slice(0, state.cols); }
    }
    if (line.length) lines.push(line);
  }
  lines = lines.slice(0, state.rows);
  lines.forEach((ln, r) => {
    ln = ln.slice(0, state.cols);
    let start = 0;
    if (align === "center") start = Math.floor((state.cols - ln.length) / 2);
    if (align === "right") start = state.cols - ln.length;
    for (let i = 0; i < ln.length; i++){
      const col = start + i;
      if (col >= 0 && col < state.cols) grid[r][col] = ln[i];
    }
  });
  return grid;
}

function renderText(text){
  const grid = layout(text);
  for (let r = 0; r < state.rows; r++)
    for (let c = 0; c < state.cols; c++)
      setCell(r, c, grid[r][c]);
  return grid;
}

/* ---------- hardware I/O ---------- */
async function sendText(text){
  const grid = renderText(text);            // optimistic local preview
  if (!state.connected || !state.host) return;
  try {
    const res = await fetch(hostUrl("/api/text"), {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        rows: state.rows, cols: state.cols,
        align: $("align").value,
        text: text.toUpperCase(),
        grid: grid.map(row => row.join(""))
      })
    });
    if (!res.ok) throw new Error("HTTP " + res.status);
  } catch (e){
    setStatus("connecting", "Send failed: " + e.message);
  }
}

function hostUrl(path){
  let h = state.host.trim();
  if (!/^https?:\/\//.test(h)) h = "http://" + h;
  return h.replace(/\/+$/, "") + path;
}
function wsUrl(){
  let h = state.host.trim().replace(/^https?:\/\//, "").replace(/\/+$/, "");
  return "ws://" + h + "/ws";
}

function connect(){
  state.host = $("host").value.trim();
  saveCfg();
  if (!state.host){ setStatus("off", "Enter a host first"); return; }
  setStatus("connecting", "Connecting to " + state.host + "…");
  // pull status once over HTTP
  fetch(hostUrl("/api/status")).then(r => r.json()).then(applyStatus).catch(()=>{});
  // open live socket
  try {
    if (state.ws) state.ws.close();
    const ws = new WebSocket(wsUrl());
    state.ws = ws;
    ws.onopen = () => { state.connected = true; setStatus("ok", "Connected — " + state.host); };
    ws.onclose = () => { state.connected = false; setStatus("off", "Disconnected"); };
    ws.onerror = () => setStatus("connecting", "Socket error (still trying HTTP)");
    ws.onmessage = (ev) => { try { applyStatus(JSON.parse(ev.data)); } catch {} };
  } catch (e){ setStatus("connecting", "WS unavailable: " + e.message); }
}

function applyStatus(s){
  if (!s) return;
  state.connected = true;
  setStatus("ok", "Connected — " + state.host);
  if (typeof s.modules === "number") $("statModules").textContent = s.modules;
  if (typeof s.homed === "number") $("statHomed").textContent = s.homed + " / " + (s.modules ?? "?");
  if (typeof s.moving === "number") $("statMoving").textContent = s.moving;
  if (s.firmware) $("statFw").textContent = s.firmware;
  if (s.rows && s.cols && (s.rows !== state.rows || s.cols !== state.cols)){
    state.rows = s.rows; state.cols = s.cols;
    $("rows").value = s.rows; $("cols").value = s.cols; buildBoard();
  }
  // reflect live module glyphs if reported
  if (Array.isArray(s.grid)){
    s.grid.forEach((line, r) => {
      for (let c = 0; c < line.length; c++) setCell(r, c, line[c]);
    });
  }
}

function setStatus(kind, text){
  const dot = $("statusDot");
  dot.className = "dot" + (kind === "ok" ? " ok" : kind === "connecting" ? " connecting" : "");
  $("statusText").textContent = text;
}

/* ---------- validation ---------- */
function validate(){
  const raw = $("msg").value.toUpperCase();
  const bad = [...new Set([...raw].filter(ch => ch !== "\n" && !CHARSET_SET.has(ch)))];
  const hint = $("charHint");
  if (bad.length){
    hint.innerHTML = `<span class="invalid">Not on the drum (shown blank): ${bad.map(escapeHtml).join(" ")}</span>`;
  } else {
    hint.textContent = `${raw.replace(/\n/g,"").length} chars · all supported`;
  }
}
function escapeHtml(s){ return s.replace(/[&<>]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;"}[c])); }

/* ---------- wire up ---------- */
function init(){
  loadCfg();
  buildBoard();
  $("legend").textContent = "Drum: " + FLAP_COUNT + " flaps — " + CHARSET.map(c => c === " " ? "␣" : c).join("");
  validate();

  $("sendBtn").onclick = () => sendText($("msg").value);
  $("helloBtn").onclick = () => { $("msg").value = "HELLO WORLD"; validate(); sendText("HELLO WORLD"); };
  $("clearBtn").onclick = () => { $("msg").value = ""; validate(); sendText(""); };
  $("msg").addEventListener("input", validate);
  $("connectBtn").onclick = connect;
  $("applyGrid").onclick = () => {
    state.rows = Math.max(1, Math.min(16, +$("rows").value || 4));
    state.cols = Math.max(1, Math.min(32, +$("cols").value || 16));
    saveCfg(); buildBoard(); renderText($("msg").value);
  };

  // first paint
  setTimeout(() => renderText($("msg").value), 150);
}
init();
</script>
</body>
</html>

)rawliteral";
