---
name: publish-setup
description: Use when Calum wants to set up Apple app distribution for a repo or ship an iOS app to TestFlight. One up-front interview surfaces only the human-only Apple steps (Developer Program enrollment, the one App Store Connect API key, the match git auth), reuses the account's single shared distribution cert via fastlane match (git backend, central certificates repo), keeps the match passphrase + ASC key + git auth in 1Password (Homelab), syncs secrets/variables to GitHub, and drops in self-installing CI that ships iOS to TestFlight on a version tag. Triggers: "get this on TestFlight", "set up signing", "publish this app", "ship to the App Store".
---

# publish-setup

Take any app repo to **TestFlight (iOS)** or a **notarized DMG (macOS)** with the
smallest possible manual touch. The principle: **ask up front for the few things
only a human can do, then automate everything else.** Detect current state first;
ask for nothing you can discover yourself.

Design spec: `dotfiles/docs/superpowers/specs/2026-06-08-publish-setup-skill-design.md`.

## Operating rules

- **Shared signing via `fastlane match` (git backend).** ONE Apple distribution
  certificate signs every app in the account (Apple caps active certs at ~2-3, so
  never mint per-app). It lives encrypted in a central git repo
  (`MATCH_GIT_URL`, default `github.com/0x63616c/certificates.git`). Each new app
  reuses that cert and only mints its own **provisioning profile** into the same
  repo. match has no 1Password storage backend — that's why the cert is in git —
  but the match **passphrase**, the **ASC API key**, and the repo's **git auth**
  all live in 1Password.
- **1Password is the source of truth.** Vault is always `Homelab`. ASC key,
  `match password`, `match-git-url`, `match-git-auth` live on one item (the ASC
  key item). GitHub Actions secrets/variables are a synced copy pushed by
  `sync-secrets.sh`. CI reads only GitHub, never 1Password.
- **Secrets never enter the chat.** Capturing any credential happens in an
  interactive terminal script (`save-asc-key.sh`, `save-match-git-auth.sh`),
  terminal → 1Password. Never ask Calum to paste a `.p8` / token into the chat.
- **iOS/TestFlight only** for now. The macOS notarize path predated this match
  rewrite and is not yet reworked.
- **Idempotent.** Every script is safe to re-run; second run is a near no-op.
- **The agent drives — don't narrate commands for Calum to run.** Gather required
  info as early as possible (step 0.5), then YOU run `setup-app.sh`,
  `sync-secrets.sh`, the tag, and all verification yourself, and report results.
  Ask Calum directly for any non-secret value you need (Apple ID, Team ID, bundle
  id). The ONLY things he runs are the interactive secret-capture scripts
  (`save-asc-key.sh`, `save-apple-session.sh`, `save-match-git-auth.sh`) — because
  they need a password / 2FA / token typed into a terminal, which is truly secret
  and can't pass through you. Everything else is yours. Verify each step (resolve
  the 1P item, watch the CI run, confirm the build in App Store Connect) rather
  than assuming it worked.

## Checklist (work top to bottom; create a TodoWrite item per step)

> **Front-load every human-only input before you automate anything.** Steps 0 and
> 0.5 below come first and gather ALL human-gated inputs in one batch, so Calum can
> work them in parallel (downloading the ASC key, confirming enrollment) while you
> build the rest. Do NOT start step 3+ automation and only later realize you need a
> credential — that strands Calum waiting. The rule: detect, then ask for
> everything at once, then go heads-down.

### 0. Detect state
Run, in the target repo:
- `command -v fastlane gh op` — tooling present?
- ASC key already in 1Password? Don't just check the `asc-api-key` item — an ASC
  key is **account-level and reusable across apps**, and one may already exist
  under a different title (e.g. `App Store Connect API`) with the `.p8` stored as
  a file attachment. Source `scripts/lib/asc-key.sh` and run `asc_resolve`; if it
  finds one, **skip steps 1-2 entirely** and reuse it. (`save-asc-key.sh` does
  this check itself and exits early.)
- Inspect repo to classify the app:
  - `Package.swift` or an Xcode macOS target → **macos** (notarize path).
  - `capacitor.config.*` / `ios/App/App.xcodeproj` → **ios** (TestFlight path).
  - bare web app, no native shell → tell Calum it needs Capacitor first; offer to
    add it (out of v1 scope — confirm before doing).

**Already provisioned? Switch to Day-2 mode.** If detection finds the shell,
Fastfile/Matchfile, CI workflow, and GitHub secrets all in place, the ask is
maintenance, not setup — do NOT re-run steps 1-6. Instead:
- Check the **last release workflow run** (`gh run list --workflow=<release yml>`)
  before declaring the pipeline healthy — a red latest run is the real work.
  Diff the last green vs first red run's tool versions (fastlane, Xcode, runner
  image); an uncommitted/floating Gemfile.lock is the usual culprit.
- Verify the **ASC app record name** matches what Calum expects (it can lag a
  repo rename — control-center's record still said "The Workflow Engine" months
  after the repo moved on). Rename via `PATCH v1/appInfoLocalizations` (see 0.5).
- Confirm the latest build actually reached TestFlight via the ASC API
  (`GET v1/builds?filter[app]=<id>&sort=-uploadedDate` → `processingState=VALID`),
  not just a green CI run.

### 0.5. The up-front interview (one batch, before any automation)
Immediately after detection, ask Calum everything only a human can supply — in a
single round of questions, not drip-fed across steps. Then start automating while
he works the manual bits. The full human-only set:
- **Apple Developer Program** — enrolled? (gates everything; see step 1.)
- **App Store Connect API key** — only if `asc_resolve` finds NO existing key
  (see step 0). A key is account-level, so a prior app's key is reused
  automatically and this becomes a no-op. If none exists, hand him the ASC path +
  `save-asc-key.sh` command NOW so he can download the `.p8` and run the script
  while you build (see step 2). This is the most common thing agents forget to
  front-load.
- **match git auth** — usually NOT human-gated: `match_git_auth` auto-derives
  `base64("0x63616c:<token>")` from the GitHub PAT already in 1Password (item
  `GitHub Personal Access Token`). Only run `save-match-git-auth.sh` if you want a
  dedicated/different token. `match password` is already on the ASC item (verify
  with `match_password`).
- **Apple Team ID** — needed for `update_code_signing_settings` (e.g.
  `X9E4HG27NK`). Confirm once; passed to `sync-secrets.sh` as a GitHub variable.
- **App Store Connect app record** — Apple's API can't create apps (`apps` is
  GET/UPDATE only). Two ways: (a) **automated** — if an Apple ID session is in
  1Password (`fastlane_session`), `setup_ios` creates the record headlessly via
  `produce`; seed it once with `save-apple-session.sh` (one 2FA, expires ~2-4
  weeks, re-run when lapsed). (b) **manual** — create it at
  appstoreconnect.apple.com → Apps → (+) → New App. Required before the first
  TestFlight upload. If `fastlane_session` is absent, front-load (a) or (b).
- **Bundle ID + app name** — default `co.worldwidewebb.<app>`; confirm once.
  **App Store Connect names are globally unique across ALL Apple accounts** —
  even unshipped reserved names collide (409 `DUPLICATE.DIFFERENT_ACCOUNT`,
  freed only by a trademark claim). Generic names ("Control Center") are
  usually squatted, so get a fallback name from Calum in this same interview.
  Only the ASC/TestFlight-visible name is constrained; `CFBundleDisplayName`
  (home screen) has no uniqueness rule. Renaming later goes through
  `PATCH v1/appInfoLocalizations/<loc_id>` (the name lives on the appInfo
  *localization*, not the app resource).
- **Capacitor (web-app repos only)** — if there's no native shell, confirm adding
  one (step 0 detection). Don't silently scaffold.
- **Hosted API base URL (Capacitor/iOS)** — a bundled offline shell can't use a
  relative `/api` path; it needs an absolute backend. Ask for the hosted URL, or
  confirm "not hosted yet" and wire it as a build-time `VITE_API_BASE` (Actions
  variable) with a documented placeholder.
- **GitHub repo** — `git remote -v` + `gh repo view <owner/repo>`. Steps 4
  (sync-secrets) and 5 (CI runs) REQUIRE a GitHub repo; a local-only repo can't.
  If none exists, ask public vs private (public = free macOS runner minutes;
  private bills 10x) before `gh repo create`. Confirm before publishing the code.

Everything below this line is yours to automate. The human-gated items (ASC key,
match git auth, enrollment) only *block* the steps that consume them (3, 4) — keep
building everything else (Capacitor shell, CI files, docs) in parallel while Calum
handles them.

### 1. Apple Developer Program (only if not enrolled)
Test enrollment by attempting an authenticated call (e.g. `setup-app.sh` dry step,
or `bundle exec fastlane spaceship` token). If unauthenticated/not enrolled, tell
Calum:
> Enroll at https://developer.apple.com/programs/enroll/ ($99/yr). Needs the Apple
> Developer iOS app + ~24-48h for approval. Re-run me once approved.
Then **stop** — nothing downstream works without it.

### 2. App Store Connect API key (only if `asc_resolve` finds none)
The key is account-level and reusable; `asc-key.sh` auto-discovers a pre-existing
one (any vault item with a `.p8`, including the `.p8` stored as a file attachment)
and `save-asc-key.sh` exits early if it finds one. Only when there is genuinely no
key anywhere: tell Calum the exact path, then hand off to the script:
> App Store Connect → Users and Access → Integrations → App Store Connect API →
> click `+` → name it "CI", role **Admin** → Generate → **Download the `.p8` now**
> (Apple only shows it once). Also copy the **Issuer ID** (top of the page) and the
> new key's **Key ID**.
Then: `bash scripts/save-asc-key.sh` — it prompts for Issuer ID, Key ID, and the
path to the downloaded `.p8`, and writes all three into 1Password.

### 3. Provision the app (per repo)
`bash scripts/setup-app.sh ios <bundle_id> <app_name>`
- Copies `templates/Fastfile` + `templates/Matchfile` + `templates/Gemfile` into
  the repo if missing.
- Reads the ASC key + match secrets from 1Password into env.
- Runs `fastlane ios setup_ios`: (1) registers the bundle ID via the ASC API
  (Spaceship ConnectAPI — `produce` insists on an Apple ID even with the API key,
  so the bundle id is bypassed to the key); (2) creates the App Store Connect app
  record — headlessly via `produce` + the stored Apple ID session if present, else
  WARNS with manual steps (Apple API can't create apps, see 0.5); (3)
  `match(type: appstore, readonly: false)` **reuses the shared distribution cert**
  and mints this app's profile into the certificates repo. No new cert.
Bundle ID convention: `co.worldwidewebb.<app>` (confirm with Calum on first run).

### 4. Sync secrets + variables to GitHub
`bash scripts/sync-secrets.sh <owner/repo> <bundle_id> [team_id] [ios_project] [initial_build_number]`
- Secrets (`gh secret set`): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`,
  `MATCH_PASSWORD`, `MATCH_GIT_URL`, `MATCH_GIT_BASIC_AUTHORIZATION`.
- Variables (`gh variable set`): `BUNDLE_ID`, `APPLE_TEAM_ID`, `IOS_PROJECT`
  (default `ios/App/App.xcodeproj`), `IOS_SCHEME` (`App`), `INITIAL_BUILD_NUMBER`.
- Also set the `VITE_API_BASE` variable here if the Capacitor app needs a hosted
  backend. Nothing secret is written to the repo tree.

### 5. Install CI
Copy `templates/release-ios.yml` → `.github/workflows/release-ios.yml`. It builds
the web app + `cap sync`, runs `match` readonly, and ships to TestFlight on a
`v*` tag. Also install the secret-leak pre-commit guard
(`templates/pre-commit-guard.sh` → `.git/hooks/pre-commit`); it blocks commits
containing `.p8`/`.p12` material or `PRIVATE KEY` blobs.

### 6. Commit + flag minutes
Commit the Fastfile/Matchfile/Gemfile/workflow (no secrets) — **and the
`Gemfile.lock`**: run `bundle lock` and commit it so CI never floats gem
versions. An uncommitted lock let control-center float onto fastlane 2.236.0,
whose altool upload rejects IPAs with "format error (259)" and killed every
TestFlight upload (CC-84ti). The template Gemfile pins fastlane for the same
reason; widen the bound only after verifying a real `upload_to_testflight` run.
A release ships on
every push to `main` that touches the app code / native config (the workflow's
`paths:` — no git tags, no version bump; the build number comes from TestFlight).
Tune `paths:` to the repo layout. If the repo is **private**, warn that macOS
runner minutes bill at 10x; public repos are free.

### 7. TestFlight readiness (Capacitor/iOS)
- **Export compliance:** add `ITSAppUsesNonExemptEncryption = false` to
  `ios/App/App/Info.plist` (true only if the app uses non-exempt crypto; standard
  HTTPS is exempt). Without it every build shows "Missing Compliance" and can't be
  distributed until answered by hand. Set it once in the shell.
- **Upload resilience:** altool often uploads the binary fine, then 500s on a
  follow-up status call; the `release` lane catches that and verifies the build
  actually landed (App Store Connect) before failing — so a real upload isn't
  reported as a red run.
- **Inviting yourself:** internal testing needs no Beta App Review. Add yourself
  (an App Store Connect user) to an Internal Testing group once at
  App Store Connect → <app> → TestFlight → Internal Testing; builds then appear in
  the TestFlight app on your device within minutes of processing. (Per-app,
  one-time; can be scripted via the ASC API but the UI is fastest.)

## What "done" looks like
Calum pushes app-code/config changes to `main` → CI builds the web app, syncs
Capacitor, pulls the shared cert + this app's profile via match, builds, and
uploads to TestFlight (auto-distributed to the internal group he's in) — zero
further manual steps, no tagging.
