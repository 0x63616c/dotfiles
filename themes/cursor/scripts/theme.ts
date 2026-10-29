import palette from "../palette/palette.json";

export type Palette = typeof palette;

export interface TokenColorRule {
  scope: string[];
  settings: { foreground?: string; fontStyle?: string };
}

/** Append an 8-bit alpha (e.g. "26") to a `#rrggbb` color. `hex` must be `#rrggbb`. */
export function alpha(hex: string, aa: string): string {
  if (hex.length !== 7) {
    throw new Error(`alpha() expects a #rrggbb color, got "${hex}"`);
  }
  return hex + aa;
}

export function buildTheme(p: Palette = palette) {
  const colors: Record<string, string> = {
    ...baseColors(p),
    ...accentColors(p),
    ...noShadow(p),
    ...editorDetail(p),
    ...chromeColors(p),
    ...gitAndDiff(p),
    ...terminalColors(p),
    ...bracketColors(p),
  };
  return {
    name: "Blackout",
    type: "dark" as const,
    semanticHighlighting: true,
    colors,
    tokenColors: tokenColors(p),
    semanticTokenColors: semanticTokens(p),
  };
}

function bracketColors(p: Palette): Record<string, string> {
  return {
    "editorBracketHighlight.foreground1": p.bracket1,
    "editorBracketHighlight.foreground2": p.bracket2,
    "editorBracketHighlight.foreground3": p.bracket3,
    "editorBracketHighlight.foreground4": p.bracket1,
    "editorBracketHighlight.foreground5": p.bracket2,
    "editorBracketHighlight.foreground6": p.bracket3,
    "editorBracketHighlight.unexpectedBracket.foreground": p.error,
  };
}

function gitAndDiff(p: Palette): Record<string, string> {
  return {
    "gitDecoration.addedResourceForeground": p.success,
    "gitDecoration.modifiedResourceForeground": p.warning,
    "gitDecoration.deletedResourceForeground": p.error,
    "gitDecoration.untrackedResourceForeground": p.success,
    "gitDecoration.ignoredResourceForeground": p.fgFaint,
    "gitDecoration.conflictingResourceForeground": p.kw,
    "editorGutter.addedBackground": p.success,
    "editorGutter.modifiedBackground": p.warning,
    "editorGutter.deletedBackground": p.error,
    "diffEditor.insertedTextBackground": alpha(p.success, "20"),
    "diffEditor.removedTextBackground": alpha(p.error, "20"),
    "diffEditor.insertedLineBackground": alpha(p.success, "14"),
    "diffEditor.removedLineBackground": alpha(p.error, "14"),
    "editorError.foreground": p.error,
    "editorWarning.foreground": p.warning,
    "editorInfo.foreground": p.accent,
    "minimapGutter.addedBackground": p.success,
    "minimapGutter.modifiedBackground": p.warning,
    "minimapGutter.deletedBackground": p.error,
  };
}

function terminalColors(p: Palette): Record<string, string> {
  return {
    "terminalCursor.foreground": p.accent,
    "terminal.ansiBlack": p.bg,
    "terminal.ansiBrightBlack": p.lineNr,
    "terminal.ansiRed": p.error,
    "terminal.ansiBrightRed": p.errorBright,
    "terminal.ansiGreen": p.success,
    "terminal.ansiBrightGreen": p.str,
    "terminal.ansiYellow": p.warning,
    "terminal.ansiBrightYellow": p.fnBright,
    "terminal.ansiBlue": p.accent,
    "terminal.ansiBrightBlue": p.accentBright,
    "terminal.ansiMagenta": p.kw,
    "terminal.ansiBrightMagenta": p.kwBright,
    "terminal.ansiCyan": p.type,
    "terminal.ansiBrightCyan": p.typeBright,
    "terminal.ansiWhite": p.ansiWhite,
    "terminal.ansiBrightWhite": p.fg,
  };
}

function chromeColors(p: Palette): Record<string, string> {
  return {
    "tab.activeBackground": p.bg,
    "tab.inactiveBackground": p.bg,
    "tab.activeForeground": p.fg,
    "tab.inactiveForeground": p.comment,
    "tab.border": p.border,
    "tab.hoverBackground": p.currentLine,
    "tab.unfocusedActiveBorder": p.border,
    "list.activeSelectionBackground": p.currentLine,
    "list.activeSelectionForeground": p.fg,
    "list.inactiveSelectionBackground": p.currentLine,
    "list.inactiveSelectionForeground": p.fg,
    "list.hoverBackground": p.currentLine,
    "list.focusOutline": p.accent,
    "button.background": p.neutral,
    "button.foreground": p.bg,
    "button.hoverBackground": p.neutralHover,
    "button.secondaryBackground": p.currentLine,
    "button.secondaryForeground": p.fg,
    "input.background": p.bg,
    "input.foreground": p.fg,
    "input.border": p.border,
    "input.placeholderForeground": p.fgFaint,
    "inputOption.activeBorder": p.accent,
    "dropdown.background": p.bg,
    "dropdown.border": p.border,
    "dropdown.foreground": p.fg,
    "quickInput.background": p.bg,
    "quickInput.foreground": p.fg,
    "pickerGroup.border": p.border,
    "pickerGroup.foreground": p.accent,
    "quickInputList.focusBackground": p.currentLine,
    "editorWidget.background": p.bg,
    "editorWidget.border": p.border,
    "editorHoverWidget.background": p.bg,
    "editorHoverWidget.border": p.border,
    "editorSuggestWidget.background": p.bg,
    "editorSuggestWidget.border": p.border,
    "editorSuggestWidget.selectedBackground": p.currentLine,
    "notifications.background": p.bg,
    "notifications.border": p.border,
    "scrollbarSlider.background": alpha(p.fg, "1a"),
    "scrollbarSlider.hoverBackground": alpha(p.fg, "2a"),
    "scrollbarSlider.activeBackground": alpha(p.fg, "3a"),
  };
}

function editorDetail(p: Palette): Record<string, string> {
  return {
    "editor.lineHighlightBackground": p.currentLine,
    "editor.lineHighlightBorder": p.transparent,
    "editor.selectionBackground": p.selection,
    "editor.selectionHighlightBackground": alpha(p.selection, "66"),
    "editor.selectionHighlightBorder": p.transparent,
    "editor.inactiveSelectionBackground": alpha(p.selection, "80"),
    "editor.wordHighlightBackground": alpha(p.selection, "66"),
    "editor.wordHighlightBorder": p.transparent,
    "editor.wordHighlightStrongBackground": alpha(p.selection, "66"),
    "editor.wordHighlightStrongBorder": p.transparent,
    "editor.findMatchBackground": alpha(p.accent, "55"),
    "editor.findMatchHighlightBackground": alpha(p.accent, "33"),
    "editorLineNumber.foreground": p.lineNr,
    "editorLineNumber.activeForeground": p.lineNrActive,
    "editorIndentGuide.background1": p.border,
    "editorIndentGuide.activeBackground1": p.borderStrong,
    "editorWhitespace.foreground": p.border,
    "editorBracketMatch.background": p.transparent,
    "editorBracketMatch.border": p.borderStrong,
    "editorRuler.foreground": p.border,
    "editorGutter.background": p.bg,
  };
}

function accentColors(p: Palette): Record<string, string> {
  return {
    "focusBorder": p.accent,
    "editorCursor.foreground": p.accent,
    "tab.activeBorder": p.accent,
    "tab.activeBorderTop": p.accent,
    "activityBar.activeBorder": p.accent,
    "activityBarBadge.background": p.accent,
    "activityBarBadge.foreground": p.bg,
    "badge.background": p.accent,
    "badge.foreground": p.bg,
    "textLink.foreground": p.accent,
    "textLink.activeForeground": p.accentBright,
    "progressBar.background": p.accent,
    "statusBarItem.remoteBackground": p.accent,
    "statusBarItem.remoteForeground": p.bg,
    "selection.background": alpha(p.accent, "44"),
  };
}

function noShadow(p: Palette): Record<string, string> {
  return {
    "widget.shadow": p.transparent,
    "scrollbar.shadow": p.transparent,
  };
}

function baseColors(p: Palette): Record<string, string> {
  return {
    "foreground": p.fg,
    "descriptionForeground": p.fgMuted,
    "errorForeground": p.error,
    "editor.background": p.bg,
    "editor.foreground": p.fg,
    "sideBar.background": p.bg,
    "sideBar.foreground": p.fgMuted,
    "sideBar.border": p.border,
    "sideBarSectionHeader.background": p.bg,
    "sideBarSectionHeader.foreground": p.fgMuted,
    "sideBarSectionHeader.border": p.border,
    "sideBarTitle.foreground": p.fgMuted,
    "activityBar.background": p.bg,
    "activityBar.foreground": p.fg,
    "activityBar.inactiveForeground": p.fgFaint,
    "activityBar.border": p.border,
    "statusBar.background": p.bg,
    "statusBar.foreground": p.fgMuted,
    "statusBar.border": p.border,
    "panel.background": p.bg,
    "panel.border": p.border,
    "terminal.background": p.bg,
    "terminal.foreground": p.fg,
    "titleBar.activeBackground": p.bg,
    "titleBar.activeForeground": p.fg,
    "titleBar.border": p.border,
    "editorGroupHeader.tabsBackground": p.bg,
    "editorGroup.border": p.border,
  };
}

function tokenColors(p: Palette): TokenColorRule[] {
  return [
    { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: p.comment, fontStyle: "italic" } },
    { scope: ["keyword", "storage", "storage.type", "storage.modifier", "keyword.control", "keyword.operator.new", "keyword.operator.expression"], settings: { foreground: p.kw } },
    { scope: ["string", "string.quoted", "string.template", "punctuation.definition.string"], settings: { foreground: p.str } },
    { scope: ["string.regexp", "constant.character.escape"], settings: { foreground: p.str } },
    { scope: ["constant.numeric", "constant.language", "constant.language.boolean", "constant.language.null", "constant.language.undefined"], settings: { foreground: p.num } },
    { scope: ["entity.name.function", "support.function", "meta.function-call.generic", "variable.function"], settings: { foreground: p.fn } },
    { scope: ["entity.name.type", "entity.name.class", "support.type", "support.class", "entity.other.inherited-class", "entity.name.namespace"], settings: { foreground: p.type } },
    { scope: ["entity.name.tag", "support.type.primitive", "support.type.builtin"], settings: { foreground: p.type } },
    { scope: ["entity.other.attribute-name"], settings: { foreground: p.fn } },
    { scope: ["variable", "variable.other", "variable.other.readwrite", "meta.definition.variable"], settings: { foreground: p.var } },
    { scope: ["variable.parameter"], settings: { foreground: p.var } },
    { scope: ["variable.other.property", "variable.other.object.property", "meta.object-literal.key", "support.variable.property"], settings: { foreground: p.var } },
    { scope: ["punctuation", "meta.brace", "keyword.operator", "punctuation.separator", "punctuation.terminator"], settings: { foreground: p.punct } },
    { scope: ["meta.decorator", "punctuation.decorator", "entity.name.function.decorator"], settings: { foreground: p.fn } },
    { scope: ["invalid", "invalid.illegal", "invalid.deprecated"], settings: { foreground: p.error } },
  ];
}

function semanticTokens(p: Palette): Record<string, string | { foreground?: string; fontStyle?: string }> {
  return {
    "keyword": p.kw,
    "string": p.str,
    "number": p.num,
    "boolean": p.num,
    "regexp": p.str,
    "function": p.fn,
    "method": p.fn,
    "function.declaration": p.fn,
    "type": p.type,
    "class": p.type,
    "interface": p.type,
    "enum": p.type,
    "enumMember": p.num,
    "typeParameter": p.type,
    "namespace": p.type,
    "variable": p.var,
    "variable.readonly": p.var,
    "parameter": p.var,
    "property": p.var,
    "decorator": p.fn,
    "operator": p.punct,
    "comment": { foreground: p.comment, fontStyle: "italic" },
  };
}
