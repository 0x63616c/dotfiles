#!/usr/bin/env bash
# Pointer speed / acceleration, including values the GUI can't reach.
#
# The Mouse & Trackpad "Tracking speed" sliders in System Settings run 0.0 to
# 3.0. The underlying defaults keys take arbitrary values, so we write them
# directly and can sit outside that range in either direction.
#
# Each value is written twice: `defaults write` persists it (the HID system
# reads the globals at login), and `hidparam.py` pokes the *running*
# IOHIDSystem so it takes effect now, without a logout. That second step is
# what System Settings does when you drag a slider.
#
# Re-run this after a fresh macOS install, or if a visit to the Mouse pane in
# System Settings clamps a value back into slider range.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mouse tracking speed. The MX Master 4 has a high-DPI sensor and no Logi
# Options+ installed to turn it down device-side, so the OS floor of 0 is what
# makes it controllable -- this is the slider's minimum, not a disabled value
# (that would be -1, which removes acceleration and ends up *faster*).
#
# 0 is as slow as macOS itself goes: the global takes a negative float without
# complaint, but there is no curve below the lowest one, so it buys nothing.
# Going slower than this means changing the sensor, not the OS -- either the
# mouse's own DPI via Logi Options+, or a userspace remapper that scales the
# deltas (`brew install --cask linearmouse`). Neither is installed, on purpose.
MOUSE_SCALING="${MOUSE_SCALING:-0}"

# Trackpad tracking speed. Was 3.0, the GUI maximum, which is far too sensitive
# on the built-in trackpad: a flick crossed the whole screen and fine targeting
# meant lifting and re-planting a finger. Halved (2026-09-21).
TRACKPAD_SCALING="${TRACKPAD_SCALING:-1.5}"

# Scroll wheel speed. GUI max 3.0.
SCROLL_SCALING="${SCROLL_SCALING:-1.0}"

defaults write -g com.apple.mouse.scaling -float "$MOUSE_SCALING"
defaults write -g com.apple.trackpad.scaling -float "$TRACKPAD_SCALING"
defaults write -g com.apple.scrollwheel.scaling -float "$SCROLL_SCALING"

# Apply to the live HID system. Keys are the IOHIDSystem equivalents of the
# three globals above; see `ioreg -c IOHIDSystem -r -d 1`.
"$here/hidparam.py" HIDMouseAcceleration "$MOUSE_SCALING"
"$here/hidparam.py" HIDTrackpadAcceleration "$TRACKPAD_SCALING"
"$here/hidparam.py" HIDMouseScrollAcceleration "$SCROLL_SCALING"

echo "pointer: mouse=$MOUSE_SCALING trackpad=$TRACKPAD_SCALING scroll=$SCROLL_SCALING (applied live)"
