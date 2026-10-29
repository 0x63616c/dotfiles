# `publish-setup` skill — design

**Date:** 2026-06-08
**Status:** Approved design, pre-implementation
**Home:** dotfiles (`claude/skills/publish-setup/`), symlinked into `~/.claude/skills/`

## Problem

Calum spins up new apps often but stalls before TestFlight because the Apple
signing / CI setup is opaque: which certs, where to get them, how CI authenticates.
He wants the smallest possible personal touch: Claude asks up front for the few
human-only things, tells him exactly where to get them, then automates everything
else — secrets into 1Password, CI that installs itself, builds that ship to
TestFlight (iOS) or a notarized DMG (macOS).

## Core principle

**One up-front interview surfaces only the irreducibly-manual steps**, each with an
exact URL / click-path and a place to paste the result. Everything after is
automated. The skill probes current state first and asks for nothing it can
discover itself.

## Scope (v1)

In scope:
- **iOS → TestFlight** (Capacitor-wrapped web app, or native iOS).
- **macOS → notarized DMG** attached to a GitHub Release (native Swift, e.g. copy-cat).

Out of scope (later):
- Mac App Store, web/homelab deploy (bosun — different mechanism, no Apple signing).

## The only manual surface (one-time, ever — not per app)

The skill detects which are already done and asks only for what's missing:

1. **Apple Developer Program enrollment** ($99/yr). Cannot be automated: Calum +
   card + Apple approval (~24-48h, requires the Apple Developer iOS app). The skill
   detects enrollment by testing the API key; if it fails / no key, it hands over
   the enroll URL and stops.
2. **App Store Connect API key.** Created once at *App Store Connect → Users and
   Access → Integrations → App Store Connect API → [+]*, **Admin** role. The `.p8`
   downloads **once** (Apple never re-shows it). Calum hands it over; the skill
   immediately stores Issuer ID + Key ID + `.p8` into 1Password (Homelab vault) via
   an interactive save-script.

That is the entire manual list. Calum never touches Keychain, certs, or iCloud by
hand. The only file ever handed over manually is that one `.p8`.

## Automated, per repo

1. **Detect app type** by inspecting the repo: `Package.swift` / Xcode macOS target
   → macOS-notarize path; Capacitor config or iOS Xcode target → TestFlight path.
2. **Register** bundle ID + App Store Connect app record via `fastlane produce`.
3. **Mint signing assets** (no `match`):
   - `fastlane cert` → distribution cert (`Apple Distribution` for TestFlight;
     `Developer ID Application` for macOS) as a `.p12`.
   - `fastlane sigh` → provisioning profile (iOS; macOS Developer ID needs none for
     notarization).
   These hit the ASC API with the stored key and auto-create/download — same
   auto-creation `match` would give, no Keychain hunting.
4. **Store** the minted `.p12` + profile + passphrase into 1Password (Homelab) as a
   per-app item. Calum never handles the files.
5. **Sync to GitHub secrets** (pattern B): the skill runs on Calum's Mac where `op`
   is already authed, does `op read`, and `gh secret set`s the values into the
   repo. **1Password is the source of truth; GitHub secrets are a synced copy.** No
   1Password service account, no runtime `op` dependency in CI.
6. **Drop in self-installing CI**: `.github/workflows/release-ios.yml` /
   `release-macos.yml`. On a pushed version tag (`v1.2.3`): build → import cert into
   a temp keychain → sign → **iOS:** upload via `fastlane pilot`; **macOS:**
   notarize + staple via `xcrun notarytool` → attach DMG to a GitHub Release. Runs
   on free GitHub-hosted standard `macos-latest` runners (free for public repos;
   private repos burn minutes at 10x — flagged to Calum at setup).
7. **Commit, push, optionally trigger the first run and watch it.**

## Why no `match`

`fastlane match` only supports `git` / `google_cloud` / `s3` /
`gitlab_secure_files` backends — **no 1Password backend exists**. Calum wants certs
in 1Password, so we use bare `fastlane cert`/`sigh` to mint, store the `.p12` in
1Password, and sync to GitHub secrets. Tradeoff vs match: match auto-*renews*
expiring certs; here renewal is re-running `fastlane cert` once (~yearly). Worth it
to keep the "everything in 1Password" rule and kill the certs-repo + service-account
complexity.

## Components

- `SKILL.md` — orchestration: up-front interview, state detection, sequencing.
- `scripts/save-asc-key.sh` — interactive 1Password save for the ASC API key
  (one-time; follows the `using-1password` save-script pattern: invalidates the
  `op` read-cache after write).
- `scripts/setup-app.sh` — idempotent `produce` + `cert` + `sigh`; stores minted
  assets into 1Password. Second run = no-op.
- `scripts/sync-secrets.sh <repo>` — `op read` → `gh secret set` for the repo.
- `templates/` — `release-ios.yml`, `release-macos.yml`, `Fastfile`, `Gemfile`.

## Secrets inventory

**1Password (Homelab vault):**
- `asc-api-key` — Issuer ID, Key ID, `.p8` contents.
- `<app>-signing` — `.p12` (base64), `.p12` passphrase, provisioning profile (iOS).

**GitHub repo secrets (synced copy, never committed):**
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64)
- `SIGNING_P12` (base64), `SIGNING_P12_PASSWORD`, `PROVISIONING_PROFILE` (iOS)

Nothing secret in the repo tree.

## Testing

- **copy-cat** (real public macOS Swift app) — live test for the notarize path.
- **Minimal Capacitor wrap** — test for the TestFlight path.
- **Idempotency** — run the skill twice; second run is a no-op (certs reused, app
  record exists, secrets unchanged).
- **Secret-leak guard** — a blocking pre-commit grep that fails the commit if any
  key material (`.p8`/`.p12` contents, `PRIVATE KEY`, base64 blobs over a length
  threshold) appears in tracked files. Harden-as-you-go invariant, not a reminder.

## Open implementation notes

- Trigger = pushed git tag `v*` (zero-touch). `workflow_dispatch` also wired as a
  manual fallback button.
- Bundle ID convention: `co.worldwidewebb.<app>` (confirm at first run).
- Detection must distinguish iOS vs macOS Xcode targets, not just "has Xcode".
