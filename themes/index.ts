import type { TuiPluginModule } from "@opencode-ai/plugin/tui";

const plugin: TuiPluginModule & { id: string } = {
  id: "themes",
  tui: async () => {},
};

export default plugin;
