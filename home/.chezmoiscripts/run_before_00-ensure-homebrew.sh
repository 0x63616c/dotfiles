#!/bin/sh
# Installs Homebrew (and, via its installer, the Xcode Command Line Tools) if missing.
# Asks for the sudo password once. Safe to re-run: does nothing when brew exists.
set -eu

find_brew() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

if brew_bin="$(find_brew)"; then
  eval "$("$brew_bin" shellenv)"
  exit 0
fi

echo "Homebrew not found: installing (you will be asked for your password once)."
sudo -v
# Keep the sudo timestamp alive while the installer runs.
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
keepalive=$!
trap 'kill "$keepalive" 2>/dev/null || true' EXIT INT TERM

NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

if brew_bin="$(find_brew)"; then
  eval "$("$brew_bin" shellenv)"
  echo "Homebrew installed: $(brew --version | head -n1)"
else
  echo "ERROR: Homebrew install finished but brew was not found." >&2
  exit 1
fi
