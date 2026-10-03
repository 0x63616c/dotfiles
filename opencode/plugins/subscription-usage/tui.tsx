/** @jsxImportSource @opentui/solid */
import { Plugin, usePlugin } from "@opencode/plugin/tui"
import { createMemo, createSignal, For, onCleanup, Show } from "solid-js"
import { countdown, createMonitor, isStale, percentLabel, providerNotice, providers, quotaPace, resetCreditsView, type ResetCredits, type State, type Window } from "./usage"
import { createDeviceUsage } from "./device"
import { contextUsage } from "./context"

const dollars = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" })

function ContextUsage(props: { sessionID: string }) {
  const context = usePlugin()
  const session = createMemo(() => context.data.session.get(props.sessionID))
  const cost = createMemo(() => context.data.session.cost(props.sessionID))
  const usage = createMemo(() => contextUsage(
    context.data.session.message.list(props.sessionID),
    context.data.location.model.list(session()?.location),
    session()?.revert?.messageID,
  ))
  return (
    <Show when={usage() || cost() > 0}>
      <box flexDirection="column">
        <text fg={context.theme.text.base}><b><u>Context</u></b></text>
        <Show when={usage()}>
          {(reading) => <>
            <text fg={context.theme.text.muted}>{`${reading().tokens.toLocaleString()} tokens`}</text>
            <Show when={reading().percent !== undefined}>
              <text fg={context.theme.text.muted}>{`${reading().percent}% used`}</text>
            </Show>
          </>}
        </Show>
        <Show when={cost() > 0}>
          <text fg={context.theme.text.muted}>{`${dollars.format(cost())} spent`}</text>
        </Show>
      </box>
    </Show>
  )
}

function UsageWindow(props: { window: Window; windows: Window[]; now: number; stale: boolean }) {
  const { theme } = usePlugin()
  const [barWidth, setBarWidth] = createSignal(20)
  const pace = createMemo(() => quotaPace(props.window, props.now, props.windows))
  const color = () => props.stale ? theme.text.muted
    : props.window.used >= 90 || (pace()?.ratio ?? 0) >= 2 ? theme.text.feedback.error.base
    : props.window.used >= 70 || (pace() && props.window.used > pace()!.elapsed)
      ? theme.text.feedback.warning.base : theme.text.feedback.success.base
  const filled = () => Math.round(props.window.used / 100 * barWidth())
  return (
    <box flexDirection="column">
      <box flexDirection="row" justifyContent="space-between">
        <text fg={theme.text.base} truncate><i>{props.window.label}</i></text>
        <text fg={color()} flexShrink={0} wrapMode="none">
          {percentLabel(props.window.used)}
          <span style={{ fg: theme.text.muted }}>
            {pace() ? ` / ${percentLabel(pace()!.elapsed)}` : " used"}
          </span>
        </text>
      </box>
      <box flexDirection="row" gap={2}>
        <box width={0} flexGrow={1} minWidth={0}
          onSizeChange={function () { setBarWidth(Math.max(0, Math.floor(this.width))) }}>
          <text wrapMode="none">
            <span style={{ fg: color() }}>{"━".repeat(filled())}</span>
            <span style={{ fg: theme.text.muted }}>{"─".repeat(barWidth() - filled())}</span>
          </text>
        </box>
        <text fg={theme.text.muted} flexShrink={0} wrapMode="none">{countdown(props.window.resetsAt, props.now)}</text>
      </box>
    </box>
  )
}

function ResetInventory(props: { credits: ResetCredits; now: number; providerNote?: string }) {
  const { theme } = usePlugin()
  const view = createMemo(() => resetCreditsView(props.credits, props.now))
  return (
    <box flexDirection="column" paddingTop={1}>
      <box flexDirection="row" justifyContent="space-between">
        <text fg={theme.text.base}><i>Resets available</i></text>
        <text fg={theme.text.muted} flexShrink={0}>{view().available}</text>
      </box>
      <For each={view().entries}>
        {(entry) => <text fg={theme.text.muted} wrapMode="word">{entry}</text>}
      </For>
      <Show when={view().note && view().note !== props.providerNote}>
        <text fg={theme.text.muted}>{view().note}</text>
      </Show>
    </box>
  )
}

function ProviderUsage(props: { name: string; state: State; now: number }) {
  const { theme } = usePlugin()
  const stale = () => isStale(props.state, props.now)
  const notice = createMemo(() => providerNotice(props.state, props.now))
  return (
    <box flexDirection="column">
      <box flexDirection="row" justifyContent="space-between" gap={1}>
        <text fg={theme.text.base} flexGrow={1} flexShrink={1} minWidth={0} truncate>
          <b>{props.name}</b>
        </text>
        <Show when={props.state.snapshot?.plan}>
          <text fg={theme.text.muted} flexShrink={0}>{props.state.snapshot?.plan}</text>
        </Show>
      </box>
      <For each={props.state.snapshot?.windows}>
        {(window) => <UsageWindow window={window} windows={props.state.snapshot?.windows ?? []} now={props.now} stale={stale()} />}
      </For>
      <Show when={props.state.snapshot?.resetCredits}>
        {(credits) => <ResetInventory credits={credits()} now={props.now} providerNote={notice()} />}
      </Show>
      <Show when={notice()}>
        <text fg={props.state.snapshot ? theme.text.muted : theme.text.feedback.warning.base} wrapMode="word">
          {notice()}
        </text>
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
    const configured = context.options.refreshSeconds
    const interval = typeof configured === "number" && Number.isFinite(configured)
      ? Math.max(60, configured) * 1000 : 120_000
    const monitor = createMonitor(
      (provider, value) => setState((previous) => ({ ...previous, [provider]: value })),
      createDeviceUsage({ interval }),
    )
    const removeContext = context.ui.slot({
      prepend: "sidebar.content",
      render: ({ sessionID }) => <ContextUsage sessionID={sessionID} />,
    })
    const removeSlot = context.ui.slot({
      append: "sidebar.content",
      render: () => (
        <box flexDirection="column" gap={1} paddingBottom={1}>
          <box flexDirection="row" justifyContent="space-between">
            <text fg={context.theme.text.base}><b><u>AI Subscriptions</u></b></text>
            <text fg={context.theme.text.muted} onMouseDown={() => void monitor.refresh()}>↻</text>
          </box>
          <ProviderUsage name="Codex" state={state().codex} now={now()} />
          <ProviderUsage name="Claude Code" state={state().claude} now={now()} />
        </box>
      ),
    })
    // The mounted app slot owns polling and clock cleanup.
    const removeApp = context.ui.slot({
      append: "app",
      render: () => {
        // Frequent local reads keep all sidebars in sync; only the shared device
        // budget decides when an actual provider request is allowed.
        monitor.start(15_000)
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
      removeContext()
    }
  },
})
