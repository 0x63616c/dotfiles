// charset.h — canonical flap ordering.
// MUST match hardware/flaps/charset.json and webapp/index.html.
// Index = physical flap position on the drum, from home (0 = blank).
#pragma once
#include <Arduino.h>

// 48-flap drum: blank + A-Z + 0-9 + 7 punctuation + 4 currency.
// Currency glyphs are multi-byte UTF-8; we map them from their input bytes.
static const char* const FLAP_GLYPHS[] = {
  " ",
  "A","B","C","D","E","F","G","H","I","J","K","L","M",
  "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
  "0","1","2","3","4","5","6","7","8","9",
  ".",",","!","?","-","/","&",
  "$","£","€","¥"   // $  £  €  ¥
};
static const uint8_t FLAP_COUNT = sizeof(FLAP_GLYPHS) / sizeof(FLAP_GLYPHS[0]);

// Map an incoming glyph (as a UTF-8 substring) to a flap index.
// ASCII letters are upper-cased; unknown glyphs -> 0 (blank).
// Returns the flap index, and advances *i past the consumed bytes.
inline uint8_t glyphToFlap(const String& s, size_t* i) {
  uint8_t b = (uint8_t)s[*i];

  // Multi-byte currency symbols (UTF-8): match then consume all their bytes.
  if (b >= 0x80) {
    struct { const char* u; uint8_t idx; } M[] = {
      {"£", 45}, {"€", 46}, {"¥", 47}, {"$", 44}
    };
    for (auto& m : M) {
      size_t len = strlen(m.u);
      if (s.length() - *i >= len && memcmp(s.c_str() + *i, m.u, len) == 0) {
        *i += len;
        return m.idx;
      }
    }
    *i += 1;         // unknown high byte — skip it
    return 0;
  }

  // Single-byte ASCII.
  *i += 1;
  char c = (char)b;
  if (c >= 'a' && c <= 'z') c -= 32;               // upper-case
  for (uint8_t k = 0; k < FLAP_COUNT; k++) {
    const char* g = FLAP_GLYPHS[k];
    if (g[1] == 0 && g[0] == c) return k;          // single-byte match
  }
  return 0;                                         // fallback: blank
}
