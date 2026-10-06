import { describe, expect, test } from "bun:test"
import { createRoot, createSignal } from "solid-js"
import type { Context, Route, SlotClaim } from "@opencode/plugin/tui/context"
import plugin from "./tui"
import { terminalTitle } from "./title"

const sessionRoute: Route = { type: "session", sessionID: "session-a" }

describe("full terminal titles", () => {
  test("preserves the complete session title, including Unicode and long names", () => {
    const title = "Updating password shortcut and email on Keychron keyboard"
    expect(terminalTitle(sessionRoute, title)).toBe(`OC | ${title}`)
    for (const length of [37, 40, 41, 500]) {
      const unicode = "🔧鍵盤é".repeat(length)
      expect(terminalTitle(sessionRoute, unicode)).toBe(`OC | ${unicode}`)
    }
  })

  test("uses OpenCode for home, missing and generated default titles", () => {
    expect(terminalTitle({ type: "home" }, "Previous session")).toBe("OpenCode")
    for (const title of [undefined, "", "  ", "New session - 2026-10-03T12:00:00.000Z", "Child session - 2026-10-03T12:00:00.000Z"]) {
      expect(terminalTitle(sessionRoute, title)).toBe("OpenCode")
    }
    expect(terminalTitle(sessionRoute, "New session plan")).toBe("OC | New session plan")
  })

  test("handles plugin pages and sanitizes terminal control characters", () => {
    expect(terminalTitle({ type: "plugin", id: "example", name: "Dashboard" })).toBe("OC | Dashboard")
    expect(terminalTitle(sessionRoute, "Line\nBEL\x07ESC\x1bC1\x9cend")).toBe("OC | Line BEL ESC C1 end")
    expect(terminalTitle({ type: "plugin", id: "example", name: "Dash\x1bboard" })).toBe("OC | Dash board")
  })

  test("reacts to loading, renames and session switches; stops when unmounted", async () => {
    // Title-only fixture must never reach a real cmux socket, even when tests
    // are launched inside a cmux terminal.
    const surfaceID = process.env.CMUX_SURFACE_ID
    delete process.env.CMUX_SURFACE_ID
    const [route, setRoute] = createSignal<Route>(sessionRoute)
    const [sessions, setSessions] = createSignal<Record<string, { title: string }>>({})
    const written: string[] = []
    let destroyed = false
    let claim: SlotClaim | undefined
    let unmount: (() => void) | undefined
    let removed = false
    const context = {
      ui: {
        router: { current: route },
        slot(input: SlotClaim) {
          claim = input
          return () => { removed = true; unmount?.() }
        },
      },
      data: { session: { get: (id: string) => sessions()[id] } },
      renderer: {
        get isDestroyed() { return destroyed },
        setTerminalTitle: (title: string) => written.push(title),
      },
    } as unknown as Context
    const cleanup = await plugin.setup(context)
    expect(claim?.append).toBe("app")
    try {
      createRoot((dispose) => {
        unmount = dispose
        claim!.render({} as never)
      })
      expect(written.at(-1)).toBe("OpenCode")
      setSessions({ "session-a": { title: "Updating password shortcut and email on Keychron keyboard" } })
      expect(written.at(-1)).toBe("OC | Updating password shortcut and email on Keychron keyboard")
      setSessions({ "session-a": { title: "Renamed session" }, "session-b": { title: "Other session" } })
      expect(written.at(-1)).toBe("OC | Renamed session")
      setRoute({ type: "session", sessionID: "session-b" })
      expect(written.at(-1)).toBe("OC | Other session")
      setRoute({ type: "home" })
      expect(written.at(-1)).toBe("OpenCode")
      setRoute({ type: "plugin", id: "example", name: "Dashboard" })
      expect(written.at(-1)).toBe("OC | Dashboard")
      destroyed = true
      const count = written.length
      setRoute(sessionRoute)
      expect(written).toHaveLength(count)
      destroyed = false
      if (typeof cleanup === "function") await cleanup()
      expect(removed).toBe(true)
      setSessions({ "session-a": { title: "After unload" } })
      expect(written).toHaveLength(count)
    } finally {
      unmount?.()
      if (surfaceID !== undefined) process.env.CMUX_SURFACE_ID = surfaceID
    }
  })
})
