#!/usr/bin/env bash
# Reports whether Geist / Geist Mono are installed on macOS.
set -euo pipefail
for font in "Geist" "Geist Mono"; do
  if system_profiler SPFontsDataType 2>/dev/null | grep -qi "$font"; then
    echo "OK   $font installed"
  else
    echo "MISS $font not found — download from https://vercel.com/font and install (open the .otf, click Install)."
  fi
done
