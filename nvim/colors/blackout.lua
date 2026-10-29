-- Blackout — true-black colorscheme, ported from themes/cursor/palette/palette.json.
-- Single source of truth for colors is that palette; keep this file in sync when it changes.

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.termguicolors = true
vim.o.background = "dark"
vim.g.colors_name = "blackout"

local c = {
  bg = "#000000",
  currentLine = "#0a0a0a",
  panel = "#0d0d0d",
  selection = "#232323",
  border = "#1a1a1a",
  borderStrong = "#2a2a2a",
  fg = "#ededed",
  fgMuted = "#8a8a8a",
  fgFaint = "#5a5a5a",
  lineNr = "#3a3a3a",
  lineNrActive = "#8a8a8a",
  accent = "#0a84ff",
  accentBright = "#3b9bff",
  success = "#34d399",
  warning = "#ffb454",
  error = "#fb5a4b",
  errorBright = "#ff7a6e",
  kw = "#9a86ff",
  kwBright = "#b07cff",
  str = "#34d399",
  fn = "#ffb454",
  fnBright = "#ffc679",
  type = "#57cdef",
  typeBright = "#7fdcf5",
  num = "#f47ea0",
  comment = "#6a6a6a",
  punct = "#9a9a9a",
  var = "#ededed",
  bracket1 = "#6f9bff",
  bracket2 = "#e0b06a",
  bracket3 = "#5cc593",
  ansiWhite = "#cfcfcf",
  neutralHover = "#d4d4d4",
}

local hl = function(group, spec)
  vim.api.nvim_set_hl(0, group, spec)
end

local groups = {
  -- Editor UI
  Normal = { fg = c.fg, bg = c.bg },
  NormalNC = { fg = c.fg, bg = c.bg },
  NormalFloat = { fg = c.fg, bg = c.bg },
  FloatBorder = { fg = c.border, bg = c.bg },
  FloatTitle = { fg = c.accent, bg = c.bg, bold = true },
  ColorColumn = { bg = c.currentLine },
  Cursor = { fg = c.bg, bg = c.fg },
  CursorLine = { bg = c.currentLine },
  CursorColumn = { bg = c.currentLine },
  CursorLineNr = { fg = c.lineNrActive, bold = true },
  LineNr = { fg = c.lineNr },
  SignColumn = { bg = c.bg },
  Folded = { fg = c.fgMuted, bg = c.currentLine },
  FoldColumn = { fg = c.lineNr, bg = c.bg },
  VertSplit = { fg = c.border },
  WinSeparator = { fg = c.border },
  Visual = { bg = c.selection },
  VisualNOS = { bg = c.selection },
  Search = { fg = c.bg, bg = c.accent },
  IncSearch = { fg = c.bg, bg = c.warning },
  CurSearch = { fg = c.bg, bg = c.accentBright },
  MatchParen = { fg = c.accentBright, bg = c.borderStrong, bold = true },
  NonText = { fg = c.fgFaint },
  Whitespace = { fg = c.border },
  SpecialKey = { fg = c.fgFaint },
  EndOfBuffer = { fg = c.bg },
  Directory = { fg = c.accent },
  Title = { fg = c.accent, bold = true },
  Conceal = { fg = c.fgMuted },
  QuickFixLine = { bg = c.currentLine, bold = true },
  Winbar = { fg = c.fgMuted, bg = c.bg },
  WinbarNC = { fg = c.fgFaint, bg = c.bg },

  -- Statusline / tabline
  StatusLine = { fg = c.fgMuted, bg = c.bg },
  StatusLineNC = { fg = c.fgFaint, bg = c.bg },
  TabLine = { fg = c.fgMuted, bg = c.bg },
  TabLineFill = { bg = c.bg },
  TabLineSel = { fg = c.fg, bg = c.currentLine },

  -- Popup menu (completion)
  Pmenu = { fg = c.fg, bg = c.panel },
  PmenuSel = { fg = c.fg, bg = c.selection, bold = true },
  PmenuSbar = { bg = c.panel },
  PmenuThumb = { bg = c.borderStrong },
  PmenuKind = { fg = c.type, bg = c.panel },
  PmenuExtra = { fg = c.fgMuted, bg = c.panel },

  -- Messages
  ErrorMsg = { fg = c.error },
  WarningMsg = { fg = c.warning },
  ModeMsg = { fg = c.fgMuted },
  MoreMsg = { fg = c.accent },
  Question = { fg = c.accent },
  MsgArea = { fg = c.fg, bg = c.bg },

  -- Spell
  SpellBad = { sp = c.error, undercurl = true },
  SpellCap = { sp = c.warning, undercurl = true },
  SpellRare = { sp = c.kw, undercurl = true },
  SpellLocal = { sp = c.accent, undercurl = true },

  -- Legacy syntax groups
  Comment = { fg = c.comment, italic = true },
  Constant = { fg = c.num },
  String = { fg = c.str },
  Character = { fg = c.str },
  Number = { fg = c.num },
  Boolean = { fg = c.num },
  Float = { fg = c.num },
  Identifier = { fg = c.fg },
  Function = { fg = c.fn },
  Statement = { fg = c.kw },
  Conditional = { fg = c.kw },
  Repeat = { fg = c.kw },
  Label = { fg = c.kw },
  Operator = { fg = c.punct },
  Keyword = { fg = c.kw },
  Exception = { fg = c.kw },
  PreProc = { fg = c.kwBright },
  Include = { fg = c.kw },
  Define = { fg = c.kwBright },
  Macro = { fg = c.kwBright },
  PreCondit = { fg = c.kwBright },
  Type = { fg = c.type },
  StorageClass = { fg = c.type },
  Structure = { fg = c.type },
  Typedef = { fg = c.type },
  Special = { fg = c.accent },
  SpecialChar = { fg = c.fnBright },
  Tag = { fg = c.kw },
  Delimiter = { fg = c.punct },
  SpecialComment = { fg = c.fgMuted, italic = true },
  Debug = { fg = c.warning },
  Underlined = { fg = c.accent, underline = true },
  Ignore = { fg = c.fgFaint },
  Error = { fg = c.error },
  Todo = { fg = c.bg, bg = c.warning, bold = true },

  -- Diff
  DiffAdd = { fg = c.success, bg = c.currentLine },
  DiffChange = { fg = c.warning, bg = c.currentLine },
  DiffDelete = { fg = c.error, bg = c.currentLine },
  DiffText = { fg = c.warning, bg = c.selection },
  diffAdded = { fg = c.success },
  diffRemoved = { fg = c.error },
  diffChanged = { fg = c.warning },

  -- Diagnostics
  DiagnosticError = { fg = c.error },
  DiagnosticWarn = { fg = c.warning },
  DiagnosticInfo = { fg = c.accent },
  DiagnosticHint = { fg = c.type },
  DiagnosticOk = { fg = c.success },
  DiagnosticUnderlineError = { sp = c.error, undercurl = true },
  DiagnosticUnderlineWarn = { sp = c.warning, undercurl = true },
  DiagnosticUnderlineInfo = { sp = c.accent, undercurl = true },
  DiagnosticUnderlineHint = { sp = c.type, undercurl = true },
  DiagnosticVirtualTextError = { fg = c.error, bg = c.bg },
  DiagnosticVirtualTextWarn = { fg = c.warning, bg = c.bg },
  DiagnosticVirtualTextInfo = { fg = c.accent, bg = c.bg },
  DiagnosticVirtualTextHint = { fg = c.type, bg = c.bg },

  -- LSP
  LspReferenceText = { bg = c.selection },
  LspReferenceRead = { bg = c.selection },
  LspReferenceWrite = { bg = c.selection },
  LspInlayHint = { fg = c.fgFaint, bg = c.bg, italic = true },
  LspCodeLens = { fg = c.fgFaint, italic = true },
  LspSignatureActiveParameter = { fg = c.accent, bold = true },

  -- Treesitter
  ["@comment"] = { link = "Comment" },
  ["@comment.error"] = { fg = c.bg, bg = c.error, bold = true },
  ["@comment.warning"] = { fg = c.bg, bg = c.warning, bold = true },
  ["@comment.todo"] = { fg = c.bg, bg = c.accent, bold = true },
  ["@comment.note"] = { fg = c.bg, bg = c.type, bold = true },
  ["@keyword"] = { fg = c.kw },
  ["@keyword.function"] = { fg = c.kw },
  ["@keyword.return"] = { fg = c.kw },
  ["@keyword.operator"] = { fg = c.kw },
  ["@keyword.import"] = { fg = c.kw },
  ["@keyword.conditional"] = { fg = c.kw },
  ["@keyword.repeat"] = { fg = c.kw },
  ["@keyword.exception"] = { fg = c.kw },
  ["@keyword.coroutine"] = { fg = c.kw },
  ["@string"] = { fg = c.str },
  ["@string.escape"] = { fg = c.fnBright },
  ["@string.special"] = { fg = c.fnBright },
  ["@string.regexp"] = { fg = c.fnBright },
  ["@character"] = { fg = c.str },
  ["@number"] = { fg = c.num },
  ["@number.float"] = { fg = c.num },
  ["@boolean"] = { fg = c.num },
  ["@constant"] = { fg = c.num },
  ["@constant.builtin"] = { fg = c.num },
  ["@constant.macro"] = { fg = c.kwBright },
  ["@function"] = { fg = c.fn },
  ["@function.call"] = { fg = c.fn },
  ["@function.builtin"] = { fg = c.fnBright },
  ["@function.macro"] = { fg = c.fnBright },
  ["@function.method"] = { fg = c.fn },
  ["@function.method.call"] = { fg = c.fn },
  ["@constructor"] = { fg = c.type },
  ["@parameter"] = { fg = c.fg },
  ["@variable"] = { fg = c.var },
  ["@variable.builtin"] = { fg = c.kwBright },
  ["@variable.parameter"] = { fg = c.fg },
  ["@variable.member"] = { fg = c.fg },
  ["@property"] = { fg = c.fg },
  ["@field"] = { fg = c.fg },
  ["@type"] = { fg = c.type },
  ["@type.builtin"] = { fg = c.typeBright },
  ["@type.definition"] = { fg = c.type },
  ["@type.qualifier"] = { fg = c.kw },
  ["@attribute"] = { fg = c.fn },
  ["@namespace"] = { fg = c.type },
  ["@module"] = { fg = c.type },
  ["@operator"] = { fg = c.punct },
  ["@punctuation.delimiter"] = { fg = c.punct },
  ["@punctuation.bracket"] = { fg = c.punct },
  ["@punctuation.special"] = { fg = c.accent },
  ["@tag"] = { fg = c.kw },
  ["@tag.builtin"] = { fg = c.kw },
  ["@tag.attribute"] = { fg = c.fn },
  ["@tag.delimiter"] = { fg = c.punct },
  ["@label"] = { fg = c.kw },
  ["@markup.heading"] = { fg = c.accent, bold = true },
  ["@markup.strong"] = { fg = c.num, bold = true },
  ["@markup.italic"] = { fg = c.fn, italic = true },
  ["@markup.link"] = { fg = c.accent },
  ["@markup.link.label"] = { fg = c.accentBright },
  ["@markup.raw"] = { fg = c.str },
  ["@markup.list"] = { fg = c.accent },
  ["@markup.quote"] = { fg = c.fgMuted, italic = true },

  -- LSP semantic tokens
  ["@lsp.type.class"] = { fg = c.type },
  ["@lsp.type.interface"] = { fg = c.type },
  ["@lsp.type.enum"] = { fg = c.type },
  ["@lsp.type.enumMember"] = { fg = c.num },
  ["@lsp.type.namespace"] = { fg = c.type },
  ["@lsp.type.type"] = { fg = c.type },
  ["@lsp.type.typeParameter"] = { fg = c.typeBright },
  ["@lsp.type.function"] = { fg = c.fn },
  ["@lsp.type.method"] = { fg = c.fn },
  ["@lsp.type.property"] = { fg = c.fg },
  ["@lsp.type.variable"] = { fg = c.var },
  ["@lsp.type.parameter"] = { fg = c.fg },
  ["@lsp.type.keyword"] = { fg = c.kw },
  ["@lsp.type.string"] = { fg = c.str },
  ["@lsp.type.number"] = { fg = c.num },
  ["@lsp.type.decorator"] = { fg = c.fn },
  ["@lsp.typemod.variable.readonly"] = { fg = c.num },
  ["@lsp.typemod.variable.defaultLibrary"] = { fg = c.kwBright },

  -- Gitsigns
  GitSignsAdd = { fg = c.success },
  GitSignsChange = { fg = c.warning },
  GitSignsDelete = { fg = c.error },
  GitSignsAddNr = { fg = c.success },
  GitSignsChangeNr = { fg = c.warning },
  GitSignsDeleteNr = { fg = c.error },

  -- which-key
  WhichKey = { fg = c.accent },
  WhichKeyGroup = { fg = c.kw },
  WhichKeyDesc = { fg = c.fg },
  WhichKeySeparator = { fg = c.fgFaint },
  WhichKeyValue = { fg = c.fgMuted },
  WhichKeyFloat = { bg = c.bg },
  WhichKeyBorder = { fg = c.border, bg = c.bg },

  -- Snacks (picker / dashboard / explorer / indent)
  SnacksNormal = { fg = c.fg, bg = c.bg },
  SnacksBackdrop = { bg = c.bg },
  SnacksWinBorder = { fg = c.border, bg = c.bg },
  SnacksPickerDir = { fg = c.fgMuted },
  SnacksPickerMatch = { fg = c.accent, bold = true },
  SnacksIndent = { fg = c.border },
  SnacksIndentScope = { fg = c.borderStrong },
  SnacksDashboardHeader = { fg = c.accent },
  SnacksDashboardIcon = { fg = c.fn },
  SnacksDashboardDesc = { fg = c.fg },
  SnacksDashboardKey = { fg = c.kw },
  SnacksDashboardFooter = { fg = c.fgMuted },

  -- Neo-tree (if enabled)
  NeoTreeNormal = { fg = c.fg, bg = c.bg },
  NeoTreeNormalNC = { fg = c.fg, bg = c.bg },
  NeoTreeDirectoryIcon = { fg = c.accent },
  NeoTreeDirectoryName = { fg = c.fg },
  NeoTreeGitModified = { fg = c.warning },
  NeoTreeGitAdded = { fg = c.success },
  NeoTreeGitDeleted = { fg = c.error },
  NeoTreeGitUntracked = { fg = c.fgMuted },
  NeoTreeIndentMarker = { fg = c.border },
  NeoTreeRootName = { fg = c.accent, bold = true },

  -- blink.cmp
  BlinkCmpMenu = { fg = c.fg, bg = c.panel },
  BlinkCmpMenuBorder = { fg = c.border, bg = c.panel },
  BlinkCmpMenuSelection = { bg = c.selection, bold = true },
  BlinkCmpLabel = { fg = c.fg },
  BlinkCmpLabelMatch = { fg = c.accent, bold = true },
  BlinkCmpKind = { fg = c.type },
  BlinkCmpDoc = { fg = c.fg, bg = c.bg },
  BlinkCmpDocBorder = { fg = c.border, bg = c.bg },

  -- Flash
  FlashLabel = { fg = c.bg, bg = c.error, bold = true },
  FlashMatch = { fg = c.accent, bg = c.currentLine },
  FlashCurrent = { fg = c.warning, bg = c.currentLine },

  -- Notify / Noice
  NoiceCmdlinePopupBorder = { fg = c.accent },
  NoiceCmdlineIcon = { fg = c.accent },

  -- Rainbow brackets (rainbow-delimiters)
  RainbowDelimiterBlue = { fg = c.bracket1 },
  RainbowDelimiterYellow = { fg = c.bracket2 },
  RainbowDelimiterGreen = { fg = c.bracket3 },
  RainbowDelimiterCyan = { fg = c.type },
  RainbowDelimiterViolet = { fg = c.kw },
  RainbowDelimiterOrange = { fg = c.fn },
  RainbowDelimiterRed = { fg = c.error },

  -- Bufferline minimal
  BufferCurrent = { fg = c.fg, bg = c.currentLine },
  BufferVisible = { fg = c.fgMuted, bg = c.bg },
  BufferInactive = { fg = c.fgFaint, bg = c.bg },
}

for group, spec in pairs(groups) do
  hl(group, spec)
end

-- :terminal ANSI palette
vim.g.terminal_color_0 = "#1a1a1a"
vim.g.terminal_color_1 = c.error
vim.g.terminal_color_2 = c.success
vim.g.terminal_color_3 = c.warning
vim.g.terminal_color_4 = c.accent
vim.g.terminal_color_5 = c.kw
vim.g.terminal_color_6 = c.type
vim.g.terminal_color_7 = c.ansiWhite
vim.g.terminal_color_8 = c.fgFaint
vim.g.terminal_color_9 = c.errorBright
vim.g.terminal_color_10 = c.success
vim.g.terminal_color_11 = c.fn
vim.g.terminal_color_12 = c.accentBright
vim.g.terminal_color_13 = c.kwBright
vim.g.terminal_color_14 = c.typeBright
vim.g.terminal_color_15 = c.fg
