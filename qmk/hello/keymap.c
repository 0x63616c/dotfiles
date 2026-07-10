/* Copyright 2024 @ Keychron (https://www.keychron.com)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include QMK_KEYBOARD_H
#include "keychron_common.h"
#include <stdlib.h> // rand/srand for Hyper party mode

// Real passwords live in secrets.h (untracked, gitignored). Missing/incomplete
// is a hard error — never silently flash a placeholder in place of a password.
#if __has_include("secrets.h")
#    include "secrets.h"
#else
#    error "secrets.h missing: cp secrets.h.example secrets.h and set SECRET_PW1/PW2"
#endif
#if !defined(SECRET_PW1) || !defined(SECRET_PW2)
#    error "secrets.h must define both SECRET_PW1 and SECRET_PW2"
#endif

enum layers {
    MAC_BASE,
    MAC_FN,
    WIN_BASE,
    WIN_FN,
};

enum custom_keycodes {
    KC_HELLO = NEW_SAFE_RANGE,
    KC_BOOTBLU, // flash whole board blue then purple, then enter bootloader
};

#define BOOTBLU_MS        1000 // total delay before jumping to bootloader
#define BOOTBLU_PURPLE_MS 800  // switch blue -> purple at this point (last 200ms)

// Hyper = the four left mods the Caps/Hyper key holds down (Ctrl+Shift+Alt+Gui).
#define HYPER_MODS (MOD_BIT(KC_LCTL) | MOD_BIT(KC_LSFT) | MOD_BIT(KC_LALT) | MOD_BIT(KC_LGUI))

// Type `str` cleanly even though the Hyper mods are physically held: drop them,
// send, then restore so the held key keeps working afterward.
static void send_hyper_string(const char *str) {
    uint8_t saved = get_mods();
    clear_mods();
    send_string(str);
    set_mods(saved);
}

// Both shifts held at once toggles Caps Lock (Caps key itself is now Hyper).
// Tracked by held state, NOT a combo — so any gap works: hold left, wait, then
// add right and it still fires. Combos would require pressing both within COMBO_TERM.
static bool lsft_held = false;
static bool rsft_held = false;

// Hyper "party mode": while the Hyper mods are held, every key latches a random
// hue. Picked once on the rising edge (so it's a stable random spread, not a
// seizure-strobe), painted each frame, cleared on release -> normal effect resumes.
static uint8_t hyper_hue[RGB_MATRIX_LED_COUNT];
static bool    hyper_was_held = false;

// clang-format off
const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [MAC_BASE] = LAYOUT_109_ansi(
        KC_ESC,   KC_BRID,  KC_BRIU,  KC_MCTRL, KC_LNPAD, RGB_VAD,  RGB_VAI,  KC_MPRV,  KC_MPLY,  KC_MNXT,  KC_MUTE,  KC_VOLD,  KC_VOLU,    KC_MUTE,    KC_SNAP,  KC_SIRI,  RGB_MOD,  KC_F13,   KC_F14,   KC_F15,   KC_HELLO,
        KC_GRV,   KC_1,     KC_2,     KC_3,     KC_4,     KC_5,     KC_6,     KC_7,     KC_8,     KC_9,     KC_0,     KC_MINS,  KC_EQL,     KC_BSPC,    KC_INS,   KC_HOME,  KC_PGUP,  KC_NUM,   KC_PSLS,  KC_PAST,  KC_PMNS,
        KC_TAB,   KC_Q,     KC_W,     KC_E,     KC_R,     KC_T,     KC_Y,     KC_U,     KC_I,     KC_O,     KC_P,     KC_LBRC,  KC_RBRC,    KC_BSLS,    KC_DEL,   KC_END,   KC_PGDN,  KC_P7,    KC_P8,    KC_P9,
        KC_HYPR,  KC_A,     KC_S,     KC_D,     KC_F,     KC_G,     KC_H,     KC_J,     KC_K,     KC_L,     KC_SCLN,  KC_QUOT,              KC_ENT,                                   KC_P4,    KC_P5,    KC_P6,    KC_PPLS,
        KC_LSFT,            KC_Z,     KC_X,     KC_C,     KC_V,     KC_B,     KC_N,     KC_M,     KC_COMM,  KC_DOT,   KC_SLSH,              KC_RSFT,              KC_UP,              KC_P1,    KC_P2,    KC_P3,
        KC_LCTL,  KC_LOPTN, KC_LCMMD,                               KC_SPC,                                 KC_RCMMD, KC_ROPTN, MO(MAC_FN), KC_RCTL,    KC_LEFT,  KC_DOWN,  KC_RGHT,  KC_P0,              KC_PDOT,  KC_PENT),
    [MAC_FN] = LAYOUT_109_ansi(
        _______,  KC_F1,    KC_F2,    KC_F3,    KC_F4,    KC_F5,    KC_F6,    KC_F7,    KC_F8,    KC_F9,    KC_F10,   KC_F11,   KC_F12,     RGB_TOG,    _______,  _______,  RGB_TOG,  _______,  _______,  _______,  _______,
        _______,  BT_HST1,  BT_HST2,  BT_HST3,  P2P4G,    _______,  _______,  _______,  _______,  _______,  _______,  _______,  _______,    _______,    _______,  _______,  _______,  _______,  _______,  _______,  _______,
        RGB_TOG,  RGB_MOD,  RGB_VAI,  RGB_HUI,  RGB_SAI,  RGB_SPI,  _______,  _______,  _______,  _______,  _______,  _______,  _______,    _______,    _______,  _______,  _______,  _______,  _______,  _______,
        _______,  RGB_RMOD, RGB_VAD,  RGB_HUD,  RGB_SAD,  RGB_SPD,  _______,  _______,  _______,  _______,  _______,  _______,              _______,                                  _______,  _______,  _______,  _______,
        _______,            _______,  _______,  _______,  _______,  BAT_LVL,  NK_TOGG,  _______,  _______,  _______,  _______,              _______,              _______,            _______,  _______,  _______,  
        _______,  _______,  _______,                                _______,                                _______,  _______,  _______,    _______,    _______,  _______,  _______,  _______,            _______,  _______),
    [WIN_BASE] = LAYOUT_109_ansi(
        KC_ESC,   KC_F1,    KC_F2,    KC_F3,    KC_F4,    KC_F5,    KC_F6,    KC_F7,    KC_F8,    KC_F9,    KC_F10,   KC_F11,   KC_F12,     KC_MUTE,    KC_PSCR,  KC_CTANA, RGB_MOD,  _______,  _______,  _______,  _______,
        KC_GRV,   KC_1,     KC_2,     KC_3,     KC_4,     KC_5,     KC_6,     KC_7,     KC_8,     KC_9,     KC_0,     KC_MINS,  KC_EQL,     KC_BSPC,    KC_INS,   KC_HOME,  KC_PGUP,  KC_NUM,   KC_PSLS,  KC_PAST,  KC_PMNS,
        KC_TAB,   KC_Q,     KC_W,     KC_E,     KC_R,     KC_T,     KC_Y,     KC_U,     KC_I,     KC_O,     KC_P,     KC_LBRC,  KC_RBRC,    KC_BSLS,    KC_DEL,   KC_END,   KC_PGDN,  KC_P7,    KC_P8,    KC_P9,
        KC_HYPR,  KC_A,     KC_S,     KC_D,     KC_F,     KC_G,     KC_H,     KC_J,     KC_K,     KC_L,     KC_SCLN,  KC_QUOT,              KC_ENT,                                   KC_P4,    KC_P5,    KC_P6,    KC_PPLS,
        KC_LSFT,            KC_Z,     KC_X,     KC_C,     KC_V,     KC_B,     KC_N,     KC_M,     KC_COMM,  KC_DOT,   KC_SLSH,              KC_RSFT,              KC_UP,              KC_P1,    KC_P2,    KC_P3,
        KC_LCTL,  KC_LWIN,  KC_LALT,                                KC_SPC,                                 KC_RALT,  KC_RWIN,  MO(WIN_FN), KC_RCTL,    KC_LEFT,  KC_DOWN,  KC_RGHT,  KC_P0,              KC_PDOT,  KC_PENT),
    [WIN_FN] = LAYOUT_109_ansi(
        _______,  KC_BRID,  KC_BRIU,  KC_TASK,  KC_FILE,  RGB_VAD,  RGB_VAI,  KC_MPRV,  KC_MPLY,  KC_MNXT,  KC_MUTE,  KC_VOLD,  KC_VOLU,    RGB_TOG,    _______,  _______,  RGB_TOG,  _______,  _______,  _______,  _______,
        _______,  BT_HST1,  BT_HST2,  BT_HST3,  P2P4G,    _______,  _______,  _______,  _______,  _______,  _______,  _______,  _______,    _______,    _______,  _______,  _______,  _______,  _______,  _______,  _______,
        RGB_TOG,  RGB_MOD,  RGB_VAI,  RGB_HUI,  RGB_SAI,  RGB_SPI,  _______,  _______,  _______,  _______,  _______,  _______,  _______,    _______,    _______,  _______,  _______,  _______,  _______,  _______,
        _______,  RGB_RMOD, RGB_VAD,  RGB_HUD,  RGB_SAD,  RGB_SPD,  _______,  _______,  _______,  _______,  _______,  _______,              _______,                                  _______,  _______,  _______,  _______,
        _______,            _______,  _______,  _______,  _______,  BAT_LVL,  NK_TOGG,  _______,  _______,  _______,  _______,              _______,              _______,            _______,  _______,  _______,  
        _______,  _______,  _______,                                _______,                                _______,  _______,  _______,    _______,    _______,  _______,  _______,  _______,            _______,  _______)
};

// clang-format on
#if defined(ENCODER_MAP_ENABLE)
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][2] = {
    [MAC_BASE] = {ENCODER_CCW_CW(KC_VOLD, KC_VOLU)},
    [MAC_FN]   = {ENCODER_CCW_CW(RGB_VAD, RGB_VAI)},
    [WIN_BASE] = {ENCODER_CCW_CW(KC_VOLD, KC_VOLU)},
    [WIN_FN]   = {ENCODER_CCW_CW(RGB_VAD, RGB_VAI)},
};
#endif // ENCODER_MAP_ENABLE

static uint32_t bootblu_timer = 0; // 0 = idle; nonzero = armed, counting down to bootloader

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    if (!process_record_keychron_common(keycode, record)) {
        return false;
    }
    switch (keycode) {
        case KC_HELLO: // F16: plain = type hello; Hyper+F16 = arm the blue->purple bootloader flash
            if (record->event.pressed) {
                if ((get_mods() & HYPER_MODS) == HYPER_MODS) {
                    bootblu_timer = timer_read32();
                    if (bootblu_timer == 0) { // avoid the idle sentinel on the rare exact-zero read
                        bootblu_timer = 1;
                    }
                } else {
                    SEND_STRING("hello from custom firmware");
                }
            }
            return false;
        case KC_BOOTBLU: // still available to map elsewhere via VIA if wanted
            if (record->event.pressed) {
                bootblu_timer = timer_read32();
                if (bootblu_timer == 0) {
                    bootblu_timer = 1;
                }
            }
            return false;
        case KC_1: // Hyper + 1 -> password 1 (plain 1 otherwise)
            if (record->event.pressed && (get_mods() & HYPER_MODS) == HYPER_MODS) {
                send_hyper_string(SECRET_PW1);
                return false;
            }
            return true;
        case KC_2: // Hyper + 2 -> password 2 (plain 2 otherwise)
            if (record->event.pressed && (get_mods() & HYPER_MODS) == HYPER_MODS) {
                send_hyper_string(SECRET_PW2);
                return false;
            }
            return true;
        case KC_LSFT: // both shifts held (any gap) -> toggle Caps Lock; shift still works
            lsft_held = record->event.pressed;
            if (record->event.pressed && rsft_held) {
                tap_code(KC_CAPS);
            }
            return true;
        case KC_RSFT:
            rsft_held = record->event.pressed;
            if (record->event.pressed && lsft_held) {
                tap_code(KC_CAPS);
            }
            return true;
    }
    return true;
}

void housekeeping_task_user(void) {
    if (bootblu_timer != 0 && timer_elapsed32(bootblu_timer) >= BOOTBLU_MS) {
        reset_keyboard(); // jump to bootloader (never returns)
    }
}

bool rgb_matrix_indicators_advanced_user(uint8_t led_min, uint8_t led_max) {
    if (bootblu_timer != 0) {
        // blue for the first phase, then purple for the final stretch before bootloader
        uint8_t r = (timer_elapsed32(bootblu_timer) >= BOOTBLU_PURPLE_MS) ? 255 : 0;
        uint8_t b = 255;
        for (uint8_t i = led_min; i < led_max; i++) {
            rgb_matrix_set_color(i, r, 0, b); // (0,0,255)=blue -> (255,0,255)=purple
        }
        return false; // boot flash overrides everything else
    }
    bool hyper_held = (get_mods() & HYPER_MODS) == HYPER_MODS;
    if (hyper_held) {
        if (!hyper_was_held) { // rising edge: roll a fresh random hue per key
            srand(timer_read32());
            for (uint16_t i = 0; i < RGB_MATRIX_LED_COUNT; i++) {
                hyper_hue[i] = (uint8_t)rand();
            }
            hyper_was_held = true;
        }
        uint8_t val = rgb_matrix_get_val(); // respect current brightness
        for (uint8_t i = led_min; i < led_max; i++) {
            RGB rgb = hsv_to_rgb((HSV){hyper_hue[i], 255, val});
            rgb_matrix_set_color(i, rgb.r, rgb.g, rgb.b);
        }
        return false; // party overrides caps/normal while Hyper is held
    }
    hyper_was_held = false; // released -> re-arm for next press
    if (host_keyboard_led_state().caps_lock) {
        // Whole main typing block white: number row down to bottom row, ` .. Backspace,
        // Left-Ctrl .. Right-Ctrl. y>=10 drops the top function/media row (y=0);
        // x<=150 drops the nav cluster + numpad (x>=159). Everything else keeps its effect.
        for (uint8_t i = led_min; i < led_max; i++) {
            if (g_led_config.point[i].y >= 10 && g_led_config.point[i].x <= 150) {
                rgb_matrix_set_color(i, 255, 255, 255);
            }
        }
    }
    return false;
}
