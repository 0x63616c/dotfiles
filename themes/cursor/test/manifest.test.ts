import { test, expect } from "bun:test";
import { existsSync } from "node:fs";
import pkg from "../package.json";
import settings from "../settings.recommended.json";

test("manifest contributes the Blackout theme and the file exists", () => {
  const theme = pkg.contributes?.themes?.[0];
  expect(theme?.label).toBe("Blackout");
  expect(theme?.uiTheme).toBe("vs-dark");
  expect(existsSync(new URL("../" + theme!.path.replace(/^\.\//, ""), import.meta.url))).toBe(true);
});

test("recommended settings select Blackout + Geist Mono with ligatures", () => {
  expect(settings["workbench.colorTheme"]).toBe("Blackout");
  expect(settings["editor.fontFamily"]).toContain("Geist Mono");
  expect(settings["editor.fontLigatures"]).toBe(true);
});
