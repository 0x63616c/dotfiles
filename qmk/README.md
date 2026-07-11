# qmk — Keychron Q6 Max firmware

Self-contained. Everything for my custom keyboard firmware lives here.

## Use

```sh
cd qmk
just flash      # build + flash. Press Hyper+Esc (blue->purple) when it waits for the bootloader.
```

First run auto-bootstraps: clones the QMK fork, links the keymap, builds the venv,
and creates `secrets.h` from the template. `just doctor` shows what's set up.

## Layout

| Path | Tracked? | What |
|---|---|---|
| `0x63616c/` | yes | The keymap (`keymap.c`, `rules.mk`, `config.h`) |
| `0x63616c/secrets.h.example` | yes | Template for the passwords |
| `0x63616c/secrets.h` | **gitignored** | Real passwords — never committed/pushed |
| `justfile` | yes | Build/flash + bootstrap recipes |
| `qmk_firmware/` | **gitignored** | The 1.2G Keychron fork (own git, re-clonable) |

## Secrets

Passwords are compiled into the firmware, not stored as VIA macros:

- `0x63616c/keymap.c` types `SECRET_PW1`..`PW4` on Hyper+F13 / F14 / F15 / F16 (top-right keys).
- Real values live in `0x63616c/secrets.h` (gitignored). Missing/incomplete = hard build error.
- VIA/WebHID cannot read them (not in EEPROM). A physical flash dump still can —
  keyboard secrets are not a substitute for a password manager.

## New machine

```sh
# after cloning dotfiles
cd qmk
just bootstrap   # clones fork + submodules (~1.2G), builds venv, creates secrets.h
$EDITOR 0x63616c/secrets.h   # set real passwords
just flash
```

## Fork backup

`qmk_firmware/` tracks the `wireless_playground` branch off Keychron's repo. That branch
holds local commits with no push remote you own — if the fork's own history matters,
push it to a personal GitHub fork. This dir deliberately does **not** vendor it.
