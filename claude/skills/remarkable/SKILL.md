---
name: remarkable
description: Upload PDFs/EPUBs to Calum's reMarkable (a reMarkable Paper Pro, account calumpeterwebb@icloud.com) via the cloud API, using the `rmapi` CLI. Use whenever he asks to put/send/add a document to his reMarkable, "remarkable plz", or similar.
---

# reMarkable

Calum has one reMarkable in normal use: a **reMarkable Paper Pro**, registered to
`calumpeterwebb@icloud.com`. Transfer goes over the cloud (Wi-Fi), via the reMarkable Cloud
API — not USB. See "USB — not verified" below for why cloud is the default.

## 1. Check `rmapi` is installed and authenticated

```bash
rmapi version
```

- **Works, prints a version** → skip to step 2.
- **`command not found`** → not installed yet, or not on `PATH`. Check
  `~/go/bin/rmapi` first (that's where it landed when this skill was set up — built from
  source, see "Installing from scratch" below) and either add `~/go/bin` to `PATH` for the
  session or call it by full path.
- **Installed but errors with something auth-related** → the cached token at
  `~/Library/Application Support/rmapi/rmapi.conf` is missing or stale. Re-pair (step 1b).

### 1b. Re-pairing (only if not already authenticated)

`rmapi` needs an 8-character one-time code from reMarkable's site, valid ~5 minutes. Get it
through Calum's logged-in Chrome session rather than asking him to type anything:

1. Use Claude in Chrome to navigate to `https://my.remarkable.com/device/browser/connect`.
2. It redirects to a page titled "Verification code" (under the **Read on reMarkable** tab of
   Devices and apps) showing an 8-letter lowercase code, e.g. `doqehoca`.
3. Feed it to `rmapi` on its first prompt:

```bash
echo "<the-code>" | rmapi ls
```

That's the *same* one-time-code flow as the browser-extension pairing (confusingly — there's
a separate "Pair device" flow under the **Tablet** tab, but that one wants a code displayed
*on the physical tablet's screen*, which we can't read; don't use it). Once paired, the token
is cached and this step isn't needed again unless it's later revoked.

### Installing from scratch (only if `rmapi` isn't on the machine at all)

No `brew` formula and `go install github.com/ddvk/rmapi@latest` fails (its `go.mod` has
`replace` directives Go's module resolver rejects for a bare `go install`). Clone and build
instead:

```bash
git clone --depth 1 https://github.com/ddvk/rmapi.git
cd rmapi
go build -o rmapi .
cp rmapi ~/go/bin/rmapi   # or wherever; just keep it somewhere durable, not /tmp
```

Requires Go (`go version` — was present on this machine already).

## 2. Why cloud API, not the Chrome file-upload tool

Claude in Chrome's `file_upload` tool caps uploads at **10MB combined**. Real documents
(scanned books, datasheets) routinely blow past that — a 13MB PDF failed this way. `rmapi`
talks straight to the reMarkable Cloud API with no such artificial cap, so it's the default
path for anything non-trivially sized, not just a fallback.

## 3. Name the file *before* uploading

`rmapi` has no separate rename step — the document's title on the reMarkable is just the
local filename (minus extension). Rename/copy to a clean human-readable name first:

```bash
cp "/messy/Original_Name_-_3ed_-_[Author].pdf" "/tmp/Clean Readable Title.pdf"
```

## 4. Upload

```bash
rmapi put "/tmp/Clean Readable Title.pdf"
```

With no second argument this lands at the root of the library. `put` also takes a remote
directory as a second argument — but see the gotcha below before assuming a name you see in
`rmapi ls` is actually a directory.

## 5. Gotcha: `[f]` vs `[d]` in `rmapi ls` — most top-level entries are documents, not folders

```
[f]	Artbook
[f]	Electronics 101
[f]	Journal
[f]	Quick sheets
[d]	trash
```

`[f]` = file/document (a notebook or PDF you can open, *not* a folder you can `cd` into).
`[d]` = actual directory. On Calum's account, almost everything at the root is a document —
only `trash` is a real directory in the normal case. Trying `rmapi cd "Electronics 101"`
fails with "directory doesn't exist" precisely because it's a document, not a folder — that's
expected, not a bug. Check the tag before assuming a name is a folder to upload into.

If you do need to move a document into a real folder, quote names with spaces and do it
inside one `rmapi` interactive-shell invocation (each separate `./rmapi <cmd>` call starts
fresh at the root, so a `cd` in one invocation doesn't persist to the next):

```bash
rmapi <<'EOF'
mkdir "Some Folder"
mv "Document Name" "Some Folder"
EOF
```

## 6. USB — not verified, use only if Calum specifically asks for offline/USB transfer

Not tested this session (no reMarkable was physically plugged in). reMarkable tablets have
historically exposed a local **USB web interface** at `http://10.11.99.1` when connected via
USB-C, gated behind a **Settings → Storage → USB web interface** toggle on the device itself
— but this has changed across firmware versions and hasn't been confirmed on a Paper Pro.
Don't present this as a working method without testing it live: check
`curl -s -m 3 http://10.11.99.1` only when a cable is actually connected, and confirm the
toggle is on before concluding it doesn't work.

## Reference: verified command sequence

```bash
# 1. Confirm rmapi is there and authenticated
rmapi version
rmapi ls   # should list documents without prompting for a code

# 2. Clean filename, then upload
cp "/path/to/messy name.pdf" "/tmp/Clean Title.pdf"
rmapi put "/tmp/Clean Title.pdf"

# 3. Confirm it landed
rmapi ls | grep "Clean Title"
```
