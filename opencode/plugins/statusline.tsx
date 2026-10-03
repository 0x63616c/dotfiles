/** @jsxImportSource @opentui/solid */
import { execFileSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import type { TuiPluginModule } from "@opencode-ai/plugin/tui";
import { createMemo, createSignal, onCleanup } from "solid-js";

type GitInfo = {
  branch: string;
  dirty: boolean;
};

function abbreviateHome(value: string) {
  const home = os.homedir();
  return value === home ? "~" : value.startsWith(`${home}${path.sep}`) ? `~${value.slice(home.length)}` : value;
}

function gitInfo(cwd: string): GitInfo | undefined {
  try {
    const branch = execFileSync("git", ["branch", "--show-current"], { cwd, encoding: "utf8", timeout: 500 }).trim();
    const status = execFileSync("git", ["status", "--porcelain"], { cwd, encoding: "utf8", timeout: 500 });
    return { branch: branch || "detached", dirty: status.trim().length > 0 };
  } catch {
    return undefined;
  }
}

function Statusline(props: { api: Parameters<TuiPluginModule["tui"]>[0]; sessionID: string }) {
  const [tick, setTick] = createSignal(0);
  const theme = () => props.api.theme.current;
  const directory = createMemo(() => {
    const session = props.api.state.session.get(props.sessionID);
    return session?.directory || props.api.state.path.directory;
  });
  const git = createMemo(() => {
    tick();
    return gitInfo(directory());
  });
  const state = createMemo(() => git());
  const timer = setInterval(() => setTick((value) => value + 1), 5000);
  onCleanup(() => clearInterval(timer));

  return (
    <box gap={1}>
      <text>
        <span style={{ fg: theme().text }}>{abbreviateHome(directory())}</span>
        <span style={{ fg: theme().textMuted }}>  </span>
        <span style={{ fg: theme().textMuted }}>git(</span>
        <span style={{ fg: theme().text }}>{state()?.branch ?? "none"}</span>
        <span style={{ fg: theme().textMuted }}>)</span>
        <span style={{ fg: theme().textMuted }}>{state() ? "  " : ""}</span>
        <span style={{ fg: state()?.dirty ? theme().warning : theme().success }}>{state() ? (state()?.dirty ? "dirty" : "clean") : ""}</span>
        <span style={{ fg: theme().textMuted }}>  Hello world</span>
      </text>
    </box>
  );
}

const plugin: TuiPluginModule & { id: string } = {
  id: "statusline",
  tui: async (api) => {
    api.slots.register({
      order: 200,
      slots: {
        sidebar_footer(_ctx, props) {
          return <Statusline api={api} sessionID={props.session_id} />;
        },
      },
    });
  },
};

export default plugin;
