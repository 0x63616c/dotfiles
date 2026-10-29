import { test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { buildTheme } from "../scripts/theme";

const theme = buildTheme();

test("core surfaces are pure black", () => {
  for (const key of [
    "editor.background", "sideBar.background", "activityBar.background",
    "statusBar.background", "panel.background", "terminal.background",
    "sideBarSectionHeader.background",
  ]) {
    expect(theme.colors[key]).toBe("#000000");
  }
});

test("occurrence highlights have no outline boxes", () => {
  for (const key of [
    "editor.wordHighlightBorder", "editor.wordHighlightStrongBorder",
    "editor.selectionHighlightBorder",
  ]) {
    expect(theme.colors[key]).toBe("#00000000");
  }
});

test("default foreground is set", () => {
  expect(theme.colors["editor.foreground"]).toBe("#ededed");
  expect(theme.colors["foreground"]).toBe("#ededed");
});

test("the accent is used consistently", () => {
  for (const key of [
    "focusBorder", "editorCursor.foreground",
    "tab.activeBorder", "activityBar.activeBorder", "badge.background",
  ]) {
    expect(theme.colors[key]).toBe("#0a84ff");
  }
});

test("no live shadows", () => {
  for (const [key, value] of Object.entries(theme.colors)) {
    if (key.endsWith(".shadow")) expect(value).toBe("#00000000");
  }
});

test("current line + selection are the quiet grays", () => {
  expect(theme.colors["editor.lineHighlightBackground"]).toBe("#0a0a0a");
  expect(theme.colors["editor.lineHighlightBorder"]).toBe("#00000000");
  expect(theme.colors["editor.selectionBackground"]).toBe("#232323");
  expect(theme.colors["editorLineNumber.foreground"]).toBe("#3a3a3a");
  expect(theme.colors["editorLineNumber.activeForeground"]).toBe("#8a8a8a");
});

test("chrome surfaces stay black with white primary button", () => {
  expect(theme.colors["tab.activeBackground"]).toBe("#000000");
  expect(theme.colors["tab.inactiveForeground"]).toBe("#6a6a6a");
  expect(theme.colors["button.background"]).toBe("#ededed");
  expect(theme.colors["button.foreground"]).toBe("#000000");
  expect(theme.colors["list.activeSelectionBackground"]).toBe("#0a0a0a");
  expect(theme.colors["input.background"]).toBe("#000000");
  expect(theme.colors["quickInput.background"]).toBe("#000000");
});

test("git + terminal map to the semantic palette", () => {
  expect(theme.colors["gitDecoration.addedResourceForeground"]).toBe("#34d399");
  expect(theme.colors["gitDecoration.modifiedResourceForeground"]).toBe("#ffb454");
  expect(theme.colors["gitDecoration.deletedResourceForeground"]).toBe("#fb5a4b");
  expect(theme.colors["terminal.ansiBlue"]).toBe("#0a84ff");
  expect(theme.colors["terminal.ansiGreen"]).toBe("#34d399");
  expect(theme.colors["terminal.ansiRed"]).toBe("#fb5a4b");
});

test("bracket pairs cycle 3 muted hues", () => {
  expect(theme.colors["editorBracketHighlight.foreground1"]).toBe("#6f9bff");
  expect(theme.colors["editorBracketHighlight.foreground2"]).toBe("#e0b06a");
  expect(theme.colors["editorBracketHighlight.foreground3"]).toBe("#5cc593");
  expect(theme.colors["editorBracketHighlight.foreground4"]).toBe("#6f9bff");
  expect(theme.colors["editorBracketHighlight.unexpectedBracket.foreground"]).toBe("#fb5a4b");
});

const ROLES: Record<string, string> = {
  keyword: "#9a86ff", string: "#34d399", function: "#ffb454",
  type: "#57cdef", number: "#f47ea0", comment: "#6a6a6a",
  punctuation: "#9a9a9a", variable: "#ededed",
};

test("every syntax role has a TextMate scope rule with its color", () => {
  const used = theme.tokenColors.flatMap(r => r.settings.foreground ? [r.settings.foreground] : []);
  for (const hex of Object.values(ROLES)) {
    expect(used).toContain(hex);
  }
});

test("comments are italic in both layers", () => {
  const tm = theme.tokenColors.find(r => r.scope.includes("comment"));
  expect(tm?.settings.fontStyle).toBe("italic");
  const sem = theme.semanticTokenColors["comment"];
  expect(typeof sem === "object" && sem.fontStyle).toBe("italic");
});

test("semantic tokens cover the core roles", () => {
  for (const key of ["keyword", "string", "number", "function", "type", "variable"]) {
    expect(theme.semanticTokenColors[key]).toBeDefined();
  }
});

import palette from "../palette/palette.json";

function srgb(c: number) {
  const x = c / 255;
  return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
}
function luminance(hex: string) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return 0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b);
}
function contrast(a: string, b: string) {
  const la = luminance(a), lb = luminance(b);
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

const paletteValues = new Set(Object.values(palette));

test("every color in output is a palette color (opaque) or palette+alpha", () => {
  const values = [
    ...Object.values(theme.colors),
    ...theme.tokenColors.flatMap(r => r.settings.foreground ? [r.settings.foreground] : []),
    ...Object.values(theme.semanticTokenColors).flatMap(v => typeof v === "object" ? [v.foreground ?? ""] : [v]),
  ].filter(v => v !== "");
  for (const v of values) {
    const base = v.length === 9 ? v.slice(0, 7) : v;
    expect(paletteValues.has(base) || base === "#000000").toBe(true);
  }
});

test("every palette role is referenced in theme.ts", () => {
  const source = readFileSync(new URL("../scripts/theme.ts", import.meta.url), "utf8");
  for (const name of Object.keys(palette)) {
    if (name === "transparent") continue;
    expect(source.includes(`p.${name}`)).toBe(true);
  }
});

test("text and tokens clear the contrast floor on black", () => {
  expect(contrast(palette.fg, palette.bg)).toBeGreaterThanOrEqual(4.5);
  for (const hex of [palette.kw, palette.str, palette.fn, palette.type, palette.num]) {
    expect(contrast(hex, palette.bg)).toBeGreaterThanOrEqual(3);
  }
});

test("shape is a valid theme document", () => {
  expect(theme.type).toBe("dark");
  expect(typeof theme.colors).toBe("object");
  expect(Array.isArray(theme.tokenColors)).toBe(true);
  for (const rule of theme.tokenColors) {
    expect(Array.isArray(rule.scope)).toBe(true);
    expect(typeof rule.settings).toBe("object");
  }
});
