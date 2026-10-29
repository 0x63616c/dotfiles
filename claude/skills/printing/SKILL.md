---
name: printing
description: Print a document — PDF, HTML, Markdown, plain text, or a claude.ai Artifact — on Calum's home printer (a Brother DCP-L2550DW at CUPS queue Brother_DCP_L2550DW_series). Use whenever he asks to print something, print this off, send this to the printer, or similar. Always checks the printer is actually online first (it lives in a cupboard and isn't always plugged in) before doing anything else.
---

# Printing

Calum has one printer in normal use: a **Brother DCP-L2550DW**, monochrome laser, CUPS queue
name `Brother_DCP_L2550DW_series`. It's currently the system default. It's also physically in a
cupboard and only plugged in sometimes — treat "is it there" as a real question, not a formality.

Be proactive: when he asks to print something, just do it. Don't ask a pile of clarifying
questions first — render, check the printer, print, confirm.

## 1. Check the printer is actually there

Always do this first, before anything else:

```bash
lpstat -p Brother_DCP_L2550DW_series
```

- **"idle" or "printing"** → it's there, carry on.
- **Anything else, or the command errors** → it's off or unplugged. Say so plainly and tell
  Calum it likely needs plugging in or waking up. **Do not silently fall back to another
  printer.**
- If `lpstat -a` shows other printers, you can mention they exist, but don't use one unless
  Calum explicitly asks for it by name. This one is his only printer in normal use.

## 2. Paper size — the tray wins, not the document

**The tray has Letter paper in it.** Observed 2026-09-20: a document laid out for A4, printed
with `-o media=A4`, came back clipped at both the top and the bottom of every page after the
first. The PDF itself was verified correct (12mm margins on all 9 pages), so the clipping was
purely the A4 imaging area not fitting on Letter paper — A4 is 18mm taller, and the printer
split the loss across top and bottom.

So the rule is the opposite way round from what it looks like:

> **Match the document to the paper, not the media flag to the document.**

The paper physically in the tray is the fixed constraint. The document is the thing you
control. If a document is laid out for A4, **re-render it at Letter** rather than forcing
`-o media=A4` and hoping.

**Default to Letter** unless Calum says the tray has been changed. Letter is also the safer
default when genuinely unsure: Letter-sized output prints fine on A4 paper (you just get extra
margin at the bottom), whereas A4-sized output *clips* on Letter. The failure is asymmetric.

For HTML, that means the `@page` rule, then re-render:

```css
@page { size: Letter; margin: 13mm 12mm 14mm; }
```

Verify before printing rather than discovering it on paper — check the page size, and if you
want certainty, measure the actual ink margins:

```bash
pdfinfo out.pdf | grep -i 'page size'    # expect 612 x 792 pts (letter)
```

Keep at least ~10mm of margin all round: the DCP-L2550DW has a hardware unprintable edge of
roughly 4mm, so anything tighter risks loss even at the correct paper size.

If a printout comes back clipped, paper-size mismatch is the first thing to suspect — and
"which paper is actually in the tray" is the question to ask, not "which size is the document".

## 3. Render to PDF if the source isn't already one

`lp` prints PDFs (and a few other formats) directly. For everything else, render to PDF first
and print the PDF — it's the one format where "what you see is what prints" actually holds.

**HTML → PDF**, headless Chrome (verified working on this machine):

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=out.pdf input.html
```

Chrome prints some `task_policy_set` / `CVDisplayLinkCreateWithCGDisplay` errors to stderr on
macOS headless runs — benign, ignore them; check the exit code and that the PDF exists instead.

If Chrome isn't at that path, fall back to Chromium or Microsoft Edge (same flags, same
binary shape: `.../Contents/MacOS/<name> --headless --disable-gpu --print-to-pdf=out.pdf`).

**Markdown → PDF.** `pandoc` is installed on this machine, with `pdflatex`/`xelatex` as the PDF
engine — verified working:

```bash
pandoc input.md -o out.pdf
```

If pandoc's LaTeX path chokes on something (emoji, unusual Unicode, a table it doesn't like),
fall back to the HTML+Chrome route: `pandoc input.md -t html -o out.html` then render that with
Chrome as above.

**Plain text → PDF.** `textutil` on this Mac does **not** convert straight to PDF (it only
does txt/rtf/rtfd/html/doc/docx/odt/wordml/webarchive) — don't reach for it directly for this.
Wrap the text in a minimal HTML `<pre>` block (preserves whitespace/alignment exactly, which
matters for anything columnar or code-like) and render with Chrome:

```bash
printf '<pre style="font: 11pt monospace; white-space: pre-wrap;">%s</pre>' \
  "$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' input.txt)" > out.html
# then Chrome-to-PDF as above
```

Re-check what's actually installed before relying on any of this — tool availability can drift
between machines/updates. Don't prescribe a tool that isn't there.

**claude.ai Artifacts.** An Artifact has a local source file behind it — render *that* file
(HTML/MD/whatever it actually is), not the claude.ai URL. Fetching the URL gets you the app
shell, not the content.

## 4. Print

```bash
lp -d Brother_DCP_L2550DW_series \
   -o media=Letter \
   -o sides=two-sided-long-edge \
   -t "job title" \
   out.pdf
```

Useful `lp` options:

| Option | Effect |
|---|---|
| `-o media=Letter` / `-o media=A4` | Page size. Letter is the default — the tray has Letter in it. See §2. |
| `-o sides=two-sided-long-edge` | Duplex, long-edge flip (this queue's current default). |
| `-o sides=two-sided-short-edge` | Duplex, short-edge flip (for landscape-bound documents). |
| `-o sides=one-sided` | Single-sided. |
| `-o number-up=2` (or 4/6/9/16) | Multiple document pages per printed sheet. |
| `-P 1-4,7` | Page range/list to print, not the whole document. |
| `-n 2` | Number of copies. |
| `-o fit-to-page` | Scales content to fit the chosen media. **Shrinks text/diagrams to fit** — matching the media size to the document (§2) is the better fix for a size mismatch; reach for this only when the document's native size genuinely doesn't exist as a media option. |

## 5. It's a mono laser — flag colour-dependent content before printing it

No colour, ever. If the document uses colour to carry meaning (colour-coded status, a
heatmap, highlighted diffs, a chart with a colour-only legend), say so before printing —
it'll come out as shades of grey and may lose the distinction entirely. Heavy dark fills
(dark backgrounds, filled banners) also burn a lot of toner for a mono laser; worth a
one-line heads-up too, not a reason to refuse.

## 6. Confirm it actually finished

Don't fire-and-forget. Poll until the job leaves the queue, then report:

```bash
JOB_ID=$(lp -d Brother_DCP_L2550DW_series -o media=Letter -o sides=two-sided-long-edge \
            -t "job title" out.pdf)
echo "$JOB_ID"   # "request id is Brother_DCP_L2550DW_series-123 (1 file(s))"

# Poll until it's no longer in the not-completed queue
until ! lpstat -W not-completed -o Brother_DCP_L2550DW_series | grep -q .; do
  sleep 2
done
```

Then report back concretely, not just "done":
- page count (`pdfinfo out.pdf | grep Pages`)
- sheets of paper used after duplexing (pages ÷ 2, rounded up, if two-sided)
- media size used
- confirmation the job cleared the queue (didn't error out or sit stuck)

## Reference: verified command sequence

```bash
# 1. Printer online?
lpstat -p Brother_DCP_L2550DW_series

# 2. Render (example: HTML source)
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=out.pdf input.html

# 3. Print — media size matched to the document, not the CUPS default
lp -d Brother_DCP_L2550DW_series -o media=Letter -o sides=two-sided-long-edge \
   -t "job title" out.pdf

# 4. Confirm completion
lpstat -W not-completed -o Brother_DCP_L2550DW_series
```
