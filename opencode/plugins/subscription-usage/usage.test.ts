import { describe, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  countdown, createMonitor, fetchUsage, loadCredential, parseClaude, parseCodex,
  retryAfter, UsageError, type Provider, type Snapshot, type State,
} from "./usage"

const now = Date.parse("2026-10-02T12:00:00Z")
const snapshot: Snapshot = { fetchedAt: now, windows: [{ label: "Week", used: 29 }] }
const signal = () => new AbortController().signal
const responseFetch = (response: Response) => async () => response
const credentials = async () => ({ token: "fixture-token", accountID: "fixture-account" })

describe("provider response contracts", () => {
  test("Claude retains zero usage and scoped model limits without duplicating the session/week", () => {
    const result = parseClaude({
      five_hour: { utilization: 0, resets_at: "2026-10-02T15:00:00Z" },
      seven_day: { utilization: 29, resets_at: null },
      seven_day_sonnet: null,
      limits: [
        { kind: "session", percent: 0 },
        { kind: "weekly_all", percent: 29 },
        { kind: "weekly_scoped", percent: 57, scope: { model: { display_name: "Fable" } } },
        { kind: "weekly_scoped", percent: null, scope: { model: { display_name: "Missing" } } },
      ],
    }, now)
    expect(result.windows.map(({ label, used }) => [label, used])).toEqual([["5h", 0], ["Week", 29], ["Fable", 57]])
    expect(result.windows[0].resetsAt).toBe(now + 3 * 3600_000)
    expect(result.windows[1].resetsAt).toBeUndefined()
  })

  test("Claude works with limits-only and older scoped-window responses", () => {
    expect(parseClaude({ limits: [{ kind: "session", percent: 12 }] }).windows[0].used).toBe(12)
    const data = { seven_day_opus: { utilization: 33 }, seven_day_sonnet: { utilization: 4 } }
    expect(parseClaude(data).windows.map((w) => w.label)).toEqual(["Sonnet", "Opus"])
  })

  test("Codex labels a weekly primary window as Week, not 5h", () => {
    const result = parseCodex({
      plan_type: "pro",
      rate_limit: { primary_window: { used_percent: 0, limit_window_seconds: 604800, reset_at: now / 1000 + 604800 }, secondary_window: null },
    }, now)
    expect(result.windows).toEqual([{ label: "Week", used: 0, resetsAt: now + 604800_000 }])
    expect(result.plan).toBe("pro")
  })

  test("Codex handles both windows, relative resets, and additive model limits", () => {
    const result = parseCodex({
      rate_limit: {
        primary_window: { used_percent: 22, limit_window_seconds: 18000, reset_after_seconds: 3600 },
        secondary_window: { used_percent: 66, limit_window_seconds: 604800 },
      },
      additional_rate_limits: [null, { limit_name: "Spark", rate_limit: { primary_window: { used_percent: 3, limit_window_seconds: 18000 } } }],
    }, now)
    expect(result.windows.map((w) => w.label)).toEqual(["5h", "Week", "Spark 5h"])
    expect(result.windows[0].resetsAt).toBe(now + 3600_000)
    expect(result.windows[1].resetsAt).toBeUndefined()
  })

  test("absent, null, nonnumeric and nonfinite percentages never become zero", () => {
    for (const bad of [undefined, null, "0", NaN, Infinity]) {
      expect(() => parseClaude({ five_hour: { utilization: bad } })).toThrow("Usage unavailable")
      expect(() => parseCodex({ rate_limit: { primary_window: { used_percent: bad } } })).toThrow("Usage unavailable")
    }
    expect(parseClaude({ five_hour: { utilization: 120 } }).windows[0].used).toBe(100)
  })
})

describe("local authentication and requests", () => {
  test("explicit profile directories stay isolated and credentials are reread after rotation", async () => {
    const home = await mkdtemp(join(tmpdir(), "opencode-usage-test-"))
    try {
      const codex = join(home, "codex")
      const claude = join(home, "claude")
      await Promise.all([mkdir(codex), mkdir(claude)])
      const env = { CODEX_HOME: codex, CLAUDE_CONFIG_DIR: claude }
      await writeFile(join(codex, "auth.json"), JSON.stringify({ tokens: { access_token: "old", account_id: "selected" } }))
      await writeFile(join(claude, ".credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "claude", subscriptionType: "max" } }))
      expect(await loadCredential("codex", signal(), env, home)).toEqual({ token: "old", accountID: "selected" })
      expect(await loadCredential("claude", signal(), env, home)).toEqual({ token: "claude", plan: "max" })
      await writeFile(join(codex, "auth.json"), JSON.stringify({ tokens: { access_token: "new" } }))
      expect((await loadCredential("codex", signal(), env, home)).token).toBe("new")
      await writeFile(join(claude, ".credentials.json"), "{}")
      await expect(loadCredential("claude", signal(), env, home)).rejects.toThrow("Sign in")
    } finally {
      await rm(home, { recursive: true, force: true })
    }
  })

  test("provider headers go only to the correct HTTPS endpoint and redirects are refused", async () => {
    const requests: { url: string; init?: RequestInit }[] = []
    const transport = async (url: string, init: RequestInit) => {
      requests.push({ url: String(url), init })
      return Response.json(String(url).includes("anthropic")
        ? { five_hour: { utilization: 5 } }
        : { rate_limit: { primary_window: { used_percent: 8, limit_window_seconds: 18000 } } })
    }
    await fetchUsage("claude", signal(), { credentials, fetch: transport })
    await fetchUsage("codex", signal(), { credentials, fetch: transport })
    expect(requests[0].url).toBe("https://api.anthropic.com/api/oauth/usage")
    expect(requests[1].url).toBe("https://chatgpt.com/backend-api/wham/usage")
    const claudeHeaders = new Headers(requests[0].init?.headers)
    const codexHeaders = new Headers(requests[1].init?.headers)
    expect(claudeHeaders.get("anthropic-beta")).toBe("oauth-2025-04-20")
    expect(claudeHeaders.has("ChatGPT-Account-Id")).toBe(false)
    expect(codexHeaders.get("ChatGPT-Account-Id")).toBe("fixture-account")
    expect(codexHeaders.has("anthropic-beta")).toBe(false)
    expect(requests.every((r) => r.init?.redirect === "error")).toBe(true)
  })

  test("HTTP failures are sanitized, and 429 supplies a retry deadline", async () => {
    for (const status of [401, 403, 500]) {
      await expect(fetchUsage("codex", signal(), {
        credentials, fetch: responseFetch(new Response("secret-response-body", { status })),
      })).rejects.toThrow(status === 401 ? "refresh login" : `HTTP ${status}`)
    }
    try {
      await fetchUsage("claude", signal(), {
        credentials, fetch: responseFetch(new Response("secret", { status: 429, headers: { "retry-after": "600" } })),
      })
      throw new Error("Expected rate limiting")
    } catch (error) {
      expect(error).toBeInstanceOf(UsageError)
      expect((error as UsageError).message).toBe("Rate limited")
      expect((error as UsageError).retryAt).toBeGreaterThan(Date.now() + 590_000)
    }
  })
})

describe("refresh lifecycle", () => {
  test("providers update independently; refreshes coalesce; shutdown aborts in-flight work", async () => {
    const seen: Partial<Record<Provider, State>> = {}
    const requests: { provider: Provider; signal: AbortSignal; resolve: (value: Snapshot) => void }[] = []
    const monitor = createMonitor((provider, state) => { seen[provider] = state }, (provider, signal) =>
      new Promise<Snapshot>((resolve) => requests.push({ provider, signal, resolve })))
    const a = monitor.refresh()
    const b = monitor.refresh()
    expect(requests.length).toBe(2)
    requests.find((r) => r.provider === "codex")!.resolve(snapshot)
    await Promise.resolve()
    expect(seen.codex?.snapshot).toBe(snapshot)
    expect(seen.claude?.loading).toBe(true)
    monitor.stop()
    expect(requests.every((r) => r.signal.aborted)).toBe(true)
    requests.find((r) => r.provider === "claude")!.resolve(snapshot)
    await Promise.all([a, b])
    expect(seen.claude?.snapshot).toBeUndefined()
    await monitor.refresh()
    expect(requests.length).toBe(2)
  })

  test("network errors retain stale data, auth errors clear it, and manual refresh honours backoff", async () => {
    let time = now
    let failure: UsageError | undefined
    let calls = 0
    const seen: Partial<Record<Provider, State>> = {}
    const monitor = createMonitor((provider, state) => { seen[provider] = state }, async () => {
      calls++
      if (failure) throw failure
      return snapshot
    }, () => time)
    await monitor.refresh()
    failure = new UsageError("Rate limited", now + 300_000)
    await monitor.refresh()
    expect(seen.claude?.snapshot).toBe(snapshot)
    expect(seen.claude?.error).toBe("Rate limited")
    await monitor.refresh()
    expect(calls).toBe(4)
    time += 300_001
    failure = new UsageError("Sign in", undefined, true)
    await monitor.refresh()
    expect(seen.claude?.snapshot).toBeUndefined()
    failure = undefined
    await monitor.refresh()
    expect(seen.claude?.snapshot).toBe(snapshot)
    expect(seen.claude?.error).toBeUndefined()
    monitor.stop()
  })

  test("Retry-After accepts seconds or HTTP dates and has a conservative fallback", () => {
    expect(retryAfter("600", now)).toBe(now + 600_000)
    expect(retryAfter("Fri, 02 Oct 2026 12:10:00 GMT", now)).toBe(now + 600_000)
    expect(retryAfter(null, now)).toBe(now + 300_000)
    expect(retryAfter("0", now)).toBe(now + 60_000)
  })

  test("reset countdowns round up, handle missing resets and never invent a reset", () => {
    expect(countdown(now + 1, now)).toBe("1m")
    expect(countdown(now + 5400_000, now)).toBe("1h 30m")
    expect(countdown(now + 90000_000, now)).toBe("1d 1h")
    expect(countdown(now, now)).toBe("Reset due")
    expect(countdown(undefined, now)).toBe("Reset time unavailable")
  })
})
