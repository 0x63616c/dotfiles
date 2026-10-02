/** @jsxImportSource @opentui/solid */
import { Plugin, usePlugin } from "@opencode/plugin/tui"
import { createSignal, For, onCleanup, Show } from "solid-js"
import { countdown, createMonitor, providers, type State, type Window } from "./usage"

function UsageWindow(props: { window: Window; now: number; stale: boolean }) {
  const { theme } = usePlugin()
  const color = () => props.stale ? theme.text.muted
    : props.window.used >= 90 ? theme.text.feedback.error.base
    : props.window.used >= 70 ? theme.text.feedback.warning.base : theme.text.feedback.success.base
  const filled = () => Math.round(props.window.used / 10)
  return (
    <box flexDirection="column">
      <box flexDirection="row" justifyContent="space-between">
        <text fg={theme.text.base} truncate>{props.window.label}</text>
        <text fg={color()}>{`${Math.round(props.window.used)}% used`}</text>
      </box>
      <text>
        <span style={{ fg: color() }}>{"━".repeat(filled())}</span>
        <span style={{ fg: theme.text.muted }}>{"─".repeat(10 - filled())}</span>
        <span style={{ fg: theme.text.muted }}>{`  ${countdown(props.window.resetsAt, props.now)}`}</span>
      </text>
    </box>
  )
}

function ProviderUsage(props: { name: string; state: State; now: number }) {
  const { theme } = usePlugin()
  const stale = () => !!props.state.error || (!!props.state.snapshot && props.now - props.state.snapshot.fetchedAt > 300_000)
  return (
    <box flexDirection="column">
      <text fg={theme.text.base}>
        <b>{props.name}</b>
        <span style={{ fg: theme.text.muted }}>{props.state.snapshot?.plan ? ` · ${props.state.snapshot.plan}` : ""}</span>
        <span style={{ fg: theme.text.feedback.warning.base }}>{stale() && props.state.snapshot ? " · stale" : ""}</span>
      </text>
      <For each={props.state.snapshot?.windows}>
        {(window) => <UsageWindow window={window} now={props.now} stale={stale()} />}
      </For>
      <Show when={props.state.error}>
        <text fg={theme.text.feedback.warning.base} wrapMode="word">{props.state.error}</text>
      </Show>
      <Show when={props.state.retryAt && props.state.retryAt > props.now}>
        <text fg={theme.text.muted}>{`Retry in ${countdown(props.state.retryAt, props.now)}`}</text>
      </Show>
      <Show when={!props.state.snapshot && !props.state.error}>
        <text fg={theme.text.muted}>Loading usage…</text>
      </Show>
    </box>
  )
}

export default Plugin.define({
  id: "calum.subscription-usage",
  setup(context) {
    const [state, setState] = createSignal<Record<(typeof providers)[number], State>>({
      claude: { loading: true }, codex: { loading: true },
    })
    const [now, setNow] = createSignal(Date.now())
    const monitor = createMonitor((provider, value) => setState((previous) => ({ ...previous, [provider]: value })))
    const configured = context.options.refreshSeconds
    const interval = typeof configured === "number" && Number.isFinite(configured)
      ? Math.max(60, configured) * 1000 : 120_000
    const removeSlot = context.ui.slot({
      append: "sidebar.content",
      render: () => (
        <box flexDirection="column" gap={1} paddingBottom={1}>
          <box flexDirection="row" justifyContent="space-between">
            <text fg={context.theme.text.base}><b>Subscription usage</b></text>
            <text fg={context.theme.text.muted} onMouseDown={() => void monitor.refresh()}>↻</text>
          </box>
          <ProviderUsage name="Claude Code" state={state().claude} now={now()} />
          <ProviderUsage name="Codex" state={state().codex} now={now()} />
          <text fg={context.theme.text.muted}>Resets in · /usage-refresh</text>
        </box>
      ),
    })
    // Keymap layers need the mounted app's provider, which is not available
    // during setup in OpenCode 2.0.22. The app slot also owns polling cleanup.
    const removeApp = context.ui.slot({
      append: "app",
      render: () => {
        context.keymap.layer(() => ({
          mode: "global",
          commands: [{
            id: "calum.subscription-usage.refresh",
            title: "Refresh Claude / Codex usage",
            group: "Usage",
            palette: true,
            slash: { name: "usage-refresh" },
            run: () => monitor.refresh(),
          }],
        }))
        monitor.start(interval)
        const clock = setInterval(() => setNow(Date.now()), 30_000)
        onCleanup(() => {
          monitor.stop()
          clearInterval(clock)
        })
        return null
      },
    })

    return () => {
      monitor.stop()
      removeApp()
      removeSlot()
    }
  },
})
