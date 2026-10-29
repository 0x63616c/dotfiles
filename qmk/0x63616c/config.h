// Copyright 2024 @ Keychron (https://www.keychron.com)
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

// Wider debounce window to mask a marginal (chattering) switch — stock is 20.
// With asym_eager_defer_pk this is the stable-up window on RELEASE: a switch that
// rebounds closed within DEBOUNCE ms of opening is absorbed instead of read as a new
// press (was 30, still leaked double-spaces -> 50). Costs 50ms of key-UP latency.
// This is a stopgap; the real fix for a chattering switch is to hot-swap it.
#undef DEBOUNCE
#define DEBOUNCE 50

// Default RGB effect + speed on a fresh EEPROM: dual beacon, moderate speed (0-255).
// NOTE: only applies after an EEPROM reset (VIA stores the last-used state otherwise).
#define RGB_MATRIX_DEFAULT_MODE RGB_MATRIX_DUAL_BEACON
#define RGB_MATRIX_DEFAULT_SPD  127

