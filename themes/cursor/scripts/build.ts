import { join } from "node:path";
import { buildTheme } from "./theme";

const out = JSON.stringify(buildTheme(), null, 2) + "\n";
await Bun.write(join(import.meta.dir, "../themes/blackout-dark.json"), out);
console.log("Wrote themes/blackout-dark.json");
