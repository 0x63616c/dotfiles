# Coding account on the homelab MacBook

You run as non-admin `coding`; files and commands are on this MacBook even when
Cursor or Rex is connected from the personal Mac. Keep long-running work in Rex.

Read the project's own instructions first. Use one Git worktree and branch per
concurrent task; preserve other agents' work and do not share a working directory.

## Package and configuration ownership

- Enter the project's existing Nix dev shell and honor its runtime/package lockfiles.
  Project dependencies belong in that project, not the machine-wide configuration.
- For an experiment, `nix shell nixpkgs#<package>` or `nix run` is fine. These are
  temporary tools, not permanent host configuration. Use a pinned nixpkgs input
  when the result must be repeatable. Promote recurring tools deliberately.
- Permanent coding tools, zsh and Claude Code are owned by
  `0x63616c/world-wide-webb`, in `projects/homelab/modules/coding.nix`.
  Change that configuration through a PR; checked promotion and Comin install it.
  Do not use sudo, global npm/Homebrew installs, `nix profile install`, native
  Claude installers or self-updates as a substitute for a desired-state change.
- Shell files and Claude's selected user settings are owned by `0x63616c/dotfiles`
  through chezmoi's `coding` profile. Edit its source, not generated home files.
  See its README before applying. Do not apply the personal profile here.
- Credentials, provider login, session history and project trust remain local.
  Never copy a personal SSH private key or commit auth/session files to dotfiles.

These are workflow instructions, not an installation sandbox. Report any manual
machine change needed by a task so it can be recorded in the correct owner.
