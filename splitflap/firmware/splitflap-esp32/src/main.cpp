// ------------------------------------------------------------------
// Split-Flap display firmware for ESP32.
//
//   * Non-blocking half-step scheduler drives 1..N 28BYJ-48 modules.
//   * Each module homes against a hall sensor + magnet, then positions
//     any flap by stepping FORWARD only (drums are one-directional).
//   * Serves the web control app, a JSON HTTP API, and a status
//     WebSocket so the browser preview mirrors the real hardware.
//
// Two build profiles (see platformio.ini):
//   DRIVER_DIRECT_GPIO  -> one module wired to ESP32 pins (bring-up)
//   DRIVER_SHIFT_CHAIN  -> the full board over 74HC595 + 74HC165 chains
// ------------------------------------------------------------------
#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include "charset.h"

// ---------------- user config ----------------
#ifndef ROWS
#define ROWS 1
#endif
#ifndef COLS
#define COLS 1
#endif
static const int MODULES = ROWS * COLS;

static const char* WIFI_SSID = "YOUR_WIFI";
static const char* WIFI_PASS = "YOUR_PASSWORD";
static const char* HOSTNAME  = "splitflap";

// 28BYJ-48: 4096 half-steps per output-shaft revolution (nominal).
// Homing every revolution corrects the small real-world drift, so this
// value only needs to be close.
static const long  STEPS_PER_REV   = 4096;
static const int   HALF_STEP_US     = 1500;   // pace per half-step (µs)
static const long  HOME_OFFSET_STEPS = 0;     // magnet->blank alignment, tune per build

// Map a flap index to an absolute step position on the drum.
static inline long flapToStep(uint8_t flap) {
  return lround((double)flap * (double)STEPS_PER_REV / (double)FLAP_COUNT);
}

// 28BYJ-48 half-step coil sequence (8 phases, IN1..IN4).
static const uint8_t HALFSTEP[8] = {
  0b0001, 0b0011, 0b0010, 0b0110,
  0b0100, 0b1100, 0b1000, 0b1001
};

// =================================================================
//  DRIVER LAYER — abstract coil output + hall input for both profiles
// =================================================================
#if defined(DRIVER_DIRECT_GPIO)
  // Single module straight to GPIO. ULN2003 IN1..IN4 + hall sensor.
  static const int COIL_PINS[4] = {16, 17, 18, 19};
  static const int HALL_PIN      = 21;   // hall sensor OUT (active LOW)

  void driverBegin() {
    for (int i = 0; i < 4; i++) { pinMode(COIL_PINS[i], OUTPUT); digitalWrite(COIL_PINS[i], LOW); }
    pinMode(HALL_PIN, INPUT_PULLUP);
  }
  void driverSetCoils(int module, uint8_t bits) {
    for (int i = 0; i < 4; i++) digitalWrite(COIL_PINS[i], (bits >> i) & 1);
  }
  void driverFlush() {}
  bool driverReadHall(int module) { return digitalRead(HALL_PIN) == LOW; }

#elif defined(DRIVER_SHIFT_CHAIN)
  // Chained shift registers. Coils out via 74HC595 (4 bits/module,
  // 2 modules per register byte). Halls in via 74HC165 (1 bit/module).
  static const int OUT_DATA = 13, OUT_CLK = 14, OUT_LATCH = 27;   // 595 chain
  static const int IN_DATA  = 34, IN_CLK  = 26, IN_LATCH  = 25;   // 165 chain

  static const int OUT_BYTES = (MODULES * 4 + 7) / 8;
  static const int IN_BYTES  = (MODULES + 7) / 8;
  static uint8_t outBuf[OUT_BYTES];
  static uint8_t inBuf[IN_BYTES];

  void driverBegin() {
    pinMode(OUT_DATA, OUTPUT); pinMode(OUT_CLK, OUTPUT); pinMode(OUT_LATCH, OUTPUT);
    pinMode(IN_DATA, INPUT);   pinMode(IN_CLK, OUTPUT);  pinMode(IN_LATCH, OUTPUT);
    memset(outBuf, 0, sizeof(outBuf));
  }
  void driverSetCoils(int module, uint8_t bits) {
    int bit0 = module * 4;                 // nibble offset in the output stream
    for (int i = 0; i < 4; i++) {
      int idx = bit0 + i, byteI = idx / 8, bitI = idx % 8;
      if ((bits >> i) & 1) outBuf[byteI] |=  (1 << bitI);
      else                 outBuf[byteI] &= ~(1 << bitI);
    }
  }
  void driverFlush() {                       // shift the whole output buffer out
    digitalWrite(OUT_LATCH, LOW);
    for (int b = OUT_BYTES - 1; b >= 0; b--)
      shiftOut(OUT_DATA, OUT_CLK, MSBFIRST, outBuf[b]);
    digitalWrite(OUT_LATCH, HIGH);
  }
  static void driverPollHalls() {            // latch + read the 165 chain
    digitalWrite(IN_LATCH, LOW); digitalWrite(IN_LATCH, HIGH);
    for (int b = IN_BYTES - 1; b >= 0; b--)
      inBuf[b] = shiftIn(IN_DATA, IN_CLK, MSBFIRST);
  }
  bool driverReadHall(int module) {          // active LOW
    return ((inBuf[module / 8] >> (module % 8)) & 1) == 0;
  }
#else
  #error "Define DRIVER_DIRECT_GPIO or DRIVER_SHIFT_CHAIN"
#endif

// =================================================================
//  MODULE — one drum's state machine
// =================================================================
struct Module {
  long    curStep   = 0;
  uint8_t phase     = 0;
  uint8_t curFlap   = 0;
  uint8_t tgtFlap   = 0;
  long    remaining = 0;      // half-steps left in the current move
  bool    homed     = false;
  bool    homing    = false;
  uint32_t nextUs   = 0;

  void energize(int idx) { driverSetCoils(idx, HALFSTEP[phase]); }
  void advance(int idx) {                    // one half-step forward
    phase = (phase + 1) & 7;
    curStep = (curStep + 1) % STEPS_PER_REV;
    energize(idx);
  }
};
static Module mods[MODULES > 0 ? MODULES : 1];

static void startHome(int i) {
  mods[i].homing = true; mods[i].homed = false; mods[i].remaining = STEPS_PER_REV + 64;
}
static void gotoFlap(int i, uint8_t flap) {
  Module& m = mods[i];
  m.tgtFlap = flap % FLAP_COUNT;
  long tgt = flapToStep(m.tgtFlap);
  m.remaining = (tgt - m.curStep + STEPS_PER_REV) % STEPS_PER_REV;
}

// The scheduler: advance every module whose step is due. Called from loop().
static void tick() {
  uint32_t now = micros();
#if defined(DRIVER_SHIFT_CHAIN)
  driverPollHalls();
#endif
  bool dirty = false;
  for (int i = 0; i < MODULES; i++) {
    Module& m = mods[i];
    if (m.remaining <= 0) continue;
    if ((int32_t)(now - m.nextUs) < 0) continue;
    m.nextUs = now + HALF_STEP_US;

    if (m.homing) {
      // seek the magnet, then define this position as home
      if (driverReadHall(i)) {
        m.curStep = (STEPS_PER_REV - HOME_OFFSET_STEPS) % STEPS_PER_REV;
        m.homed = true; m.homing = false; m.curFlap = 0; m.remaining = 0;
        gotoFlap(i, m.tgtFlap);            // proceed to whatever was requested
      } else {
        m.advance(i); m.remaining--; dirty = true;
      }
      continue;
    }
    m.advance(i); m.remaining--; dirty = true;
    if (m.remaining <= 0) {
      m.curFlap = m.tgtFlap;
      driverSetCoils(i, 0);   // release coils: the 28BYJ-48's gear ratio
    }                         // holds position, so idle modules draw ~0A
  }
#if defined(DRIVER_SHIFT_CHAIN)
  if (dirty) driverFlush();
#else
  (void)dirty;
#endif
}

// =================================================================
//  TEXT -> per-module targets
// =================================================================
static void setGridFromText(const String& text) {
  // Fill MODULES flap targets from a UTF-8 string, row-major, blank-padded.
  uint8_t want[MODULES > 0 ? MODULES : 1];
  for (int i = 0; i < MODULES; i++) want[i] = 0;
  size_t i = 0; int cell = 0;
  while (i < text.length() && cell < MODULES) {
    if (text[i] == '\n') {                    // pad to end of row
      int col = cell % COLS;
      if (col != 0) cell += (COLS - col);
      i++; continue;
    }
    want[cell++] = glyphToFlap(text, &i);
  }
  for (int k = 0; k < MODULES; k++) {
    if (mods[k].homing) mods[k].tgtFlap = want[k];        // homing in progress:
                                                          // just remember the target;
                                                          // tick() drives there on home.
    else if (!mods[k].homed) { mods[k].tgtFlap = want[k]; startHome(k); }
    else gotoFlap(k, want[k]);
  }
}

// =================================================================
//  WEB — control app + JSON API + status WebSocket
// =================================================================
static AsyncWebServer server(80);
static AsyncWebSocket  ws("/ws");

static String statusJson() {
  JsonDocument d;
  d["firmware"] = "splitflap-esp32 1.0";
  d["rows"] = ROWS; d["cols"] = COLS; d["modules"] = MODULES;
  int homed = 0, moving = 0;
  for (int i = 0; i < MODULES; i++) { if (mods[i].homed) homed++; if (mods[i].remaining > 0) moving++; }
  d["homed"] = homed; d["moving"] = moving;
  JsonArray g = d["grid"].to<JsonArray>();
  for (int r = 0; r < ROWS; r++) {
    String line;
    for (int c = 0; c < COLS; c++) line += FLAP_GLYPHS[mods[r * COLS + c].curFlap];
    g.add(line);
  }
  String out; serializeJson(d, out); return out;
}

static void onWsEvent(AsyncWebSocket*, AsyncWebSocketClient* c, AwsEventType t, void*, uint8_t*, size_t) {
  if (t == WS_EVT_CONNECT) c->text(statusJson());
}

static void setupWeb() {
  ws.onEvent(onWsEvent);
  server.addHandler(&ws);

  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest* r) {
    r->send(200, "application/json", statusJson());
  });

  server.on("/api/text", HTTP_POST, [](AsyncWebServerRequest* r) {}, nullptr,
    [](AsyncWebServerRequest* r, uint8_t* data, size_t len, size_t, size_t) {
      JsonDocument d;
      if (deserializeJson(d, data, len)) { r->send(400, "text/plain", "bad json"); return; }
      String text;
      if (d["grid"].is<JsonArray>()) {           // explicit per-row layout wins
        for (JsonVariant row : d["grid"].as<JsonArray>()) { text += row.as<String>(); text += '\n'; }
      } else {
        text = d["text"].as<String>();
      }
      setGridFromText(text);
      r->send(200, "application/json", statusJson());
    });

  server.on("/", HTTP_GET, [](AsyncWebServerRequest* r) {
    r->send(200, "text/html", INDEX_HTML);       // served from index_html.h (PROGMEM)
  });

  server.begin();
}

// Broadcast status to WebSocket clients a few times a second.
static uint32_t lastPush = 0;
static void pushStatus() {
  if (millis() - lastPush < 250) return;
  lastPush = millis();
  ws.cleanupClients();
  if (ws.count()) ws.textAll(statusJson());
}

// =================================================================
void setup() {
  Serial.begin(115200);
  driverBegin();

  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("Connecting to %s", WIFI_SSID);
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) { delay(250); Serial.print("."); }
  Serial.printf("\nIP: %s  (http://%s.local)\n", WiFi.localIP().toString().c_str(), HOSTNAME);

  setupWeb();

  for (int i = 0; i < MODULES; i++) startHome(i);   // home everything on boot
}

void loop() {
  tick();
  pushStatus();
}
