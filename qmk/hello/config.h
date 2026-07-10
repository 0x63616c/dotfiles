// Copyright 2024 @ Keychron (https://www.keychron.com)
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

// Longer debounce window to mask a marginal (chattering) switch — stock is 20.
#undef DEBOUNCE
#define DEBOUNCE 30

// Default RGB effect + speed on a fresh EEPROM: dual beacon, moderate speed (0-255).
// NOTE: only applies after an EEPROM reset (VIA stores the last-used state otherwise).
#define RGB_MATRIX_DEFAULT_MODE RGB_MATRIX_DUAL_BEACON
#define RGB_MATRIX_DEFAULT_SPD  127

