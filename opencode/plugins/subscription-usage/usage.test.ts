import { describe, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  countdown, createMonitor, fetchUsage, isStale, loadCredential, parseClaude, parseCodex, parseResetCredits, percentLabel,
  providerNotice, quotaPace, resetCreditsView, retryAfter, UsageError, type Provider, type Snapshot, type State,
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
    expect(result.windows).toEqual([{ label: "Week", used: 0, resetsAt: now + 604800_000, durationSeconds: 604800 }])
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

describe("quota time and burn pace", () => {
  test("10% used at 1% of the week elapsed is 10× pace with 99% time left", () => {
    const pace = quotaPace({ label: "Week", used: 10, resetsAt: now + 604800_000 * 0.99, durationSeconds: 604800 }, now)!
    expect(pace.elapsed).toBeCloseTo(1)
    expect(pace.left).toBeCloseTo(99)
    expect(pace.ratio).toBeCloseTo(10)
    expect(percentLabel(pace.elapsed)).toBe("1%")
  })

  test("known provider durations include model weeks and actual Codex windows", () => {
    const claude = parseClaude({
      five_hour: { utilization: 10 }, seven_day: { utilization: 20 },
      limits: [{ kind: "weekly_scoped", percent: 30, scope: { model: { display_name: "Fable" } } }],
    }, now)
    expect(claude.windows.map((window) => window.durationSeconds)).toEqual([18000, 604800, 604800])
    const codex = parseCodex({ rate_limit: { primary_window: { used_percent: 10, limit_window_seconds: 86400, reset_after_seconds: 43200 } } }, now)
    expect(quotaPace(codex.windows[0], now)).toEqual({ elapsed: 50, left: 50, ratio: 0.2 })
    const unknown = parseCodex({ rate_limit: { secondary_window: { used_percent: 10, reset_after_seconds: 3600 } } }, now)
    expect(quotaPace(unknown.windows[0], now)).toBeUndefined()
  })

  test("old cached weeks, 5h and matching model resets work without a fresh API call", () => {
    const resetsAt = now + 302400_000
    const week = { label: "Week", used: 20, resetsAt }
    expect(quotaPace(week, now)?.ratio).toBeCloseTo(0.4)
    expect(quotaPace({ label: "Fable", used: 30, resetsAt }, now, [week])?.ratio).toBeCloseTo(0.6)
    expect(quotaPace({ label: "5h", used: 25, resetsAt: now + 9000_000 }, now)?.ratio).toBeCloseTo(0.5)
  })

  test("missing, invalid, expired or not-yet-started windows never invent a pace", () => {
    for (const window of [
      { label: "Unknown", used: 10, resetsAt: now + 3600_000 },
      { label: "Week", used: 10 },
      { label: "Week", used: 10, resetsAt: now, durationSeconds: 604800 },
      { label: "Week", used: 10, resetsAt: now + 3600_000, durationSeconds: null },
      { label: "Week", used: 10, resetsAt: now + 3600_000, durationSeconds: -1 },
      { label: "Week", used: 10, resetsAt: Infinity, durationSeconds: 604800 },
      { label: "Week", used: 10, resetsAt: now + 604800_001, durationSeconds: 604800 },
    ]) expect(quotaPace(window, now)).toBeUndefined()
    const first = quotaPace({ label: "Week", used: 0, resetsAt: now + 604800_000 }, now)!
    expect(first.elapsed).toBe(0)
    expect(first.ratio).toBeUndefined()
    expect(percentLabel(0.01)).toBe("<1%")
    expect(percentLabel(0)).toBe("0%")
    expect(percentLabel(2.41)).toBe("2.4%")
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
    expect(requests[2].url).toBe("https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
    const claudeHeaders = new Headers(requests[0].init?.headers)
    const codexHeaders = new Headers(requests[1].init?.headers)
    expect(claudeHeaders.get("anthropic-beta")).toBe("oauth-2025-04-20")
    expect(claudeHeaders.has("ChatGPT-Account-Id")).toBe(false)
    expect(codexHeaders.get("ChatGPT-Account-Id")).toBe("fixture-account")
    expect(codexHeaders.has("anthropic-beta")).toBe(false)
    const resetHeaders = new Headers(requests[2].init?.headers)
    expect(resetHeaders.get("ChatGPT-Account-Id")).toBe("fixture-account")
    expect(resetHeaders.get("Authorization")).toBe(codexHeaders.get("Authorization"))
    expect(resetHeaders.get("OpenAI-Beta")).toBe("codex-1")
    expect(requests[2].init?.method).toBe("GET")
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

describe("Codex banked resets", () => {
  const usage = { rate_limit: { primary_window: { used_percent: 2, limit_window_seconds: 604800 } } }

  test("parses real counts including zero, without inferring unknown data as zero", () => {
    expect(parseResetCredits({ available_count: 2 }, now)).toEqual({ available: 2, fetchedAt: now })
    expect(parseResetCredits({ available_count: 0 }, now).available).toBe(0)
    for (const bad of [undefined, null, "2", -1, 1.5, NaN, Infinity]) {
      expect(() => parseResetCredits({ available_count: bad })).toThrow("Reset inventory unavailable")
    }
    expect(resetCreditsView({ available: 2, fetchedAt: now }, now)).toEqual({
      available: 2, entries: ["1 - Expiry unavailable", "2 - Expiry unavailable"], note: undefined,
    })
    expect(resetCreditsView({ available: 1, fetchedAt: now }, now).available).toBe(1)
    expect(resetCreditsView({ available: 0, fetchedAt: now }, now).entries).toEqual([])
    expect(resetCreditsView({ available: 2, fetchedAt: now }, now + 720_000).note).toBe("Updated 12m ago")
  })

  test("reads inventory once alongside usage, without storing credit IDs or other inventory details", async () => {
    const requests: string[] = []
    const result = await fetchUsage("codex", signal(), { credentials, fetch: async (url) => {
      requests.push(url)
      return Response.json(url.endsWith("/usage") ? usage
        : { available_count: 2, credits: [{ id: "private-credit-id", status: "available" }] })
    } })
    expect(requests.length).toBe(2)
    expect(result.windows[0].used).toBe(2)
    expect(result.resetCredits?.available).toBe(2)
    expect(JSON.stringify(result)).not.toContain("private-credit-id")
  })

  test("keeps expiry dates only for available resets and ignores invalid/missing dates", () => {
    const expires = Date.parse("2026-10-22T21:04:30Z")
    const later = Date.parse("2026-10-29T19:12:49Z")
    const credits = parseResetCredits({ available_count: 2, credits: [
      { id: "private-id", status: "available", expires_at: "2026-10-29T19:12:49Z" },
      { status: "redeemed", expires_at: "2026-10-10T00:00:00Z" },
      { status: "expired", expires_at: "2026-10-01T00:00:00Z" },
      { status: "available", expires_at: null },
      { status: "available", expires_at: "invalid" },
      { status: "available", expires_at: "2026-10-22T21:04:30Z" },
    ] }, now)
    expect(credits.expiresAt).toEqual([expires, later])
    expect(JSON.stringify(credits)).not.toContain("private-id")
    expect(resetCreditsView(credits, now).entries).toEqual(["1 - Expires 22 Oct 2026", "2 - Expires 29 Oct 2026"])
    expect(resetCreditsView({ available: 2, fetchedAt: now, expiresAt: [expires, expires] }, now).entries)
      .toEqual(["1 - Expires 22 Oct 2026", "2 - Expires 22 Oct 2026"])
    expect(resetCreditsView(credits, expires).available).toBe(1)
    expect(resetCreditsView(credits, expires).entries).toEqual(["1 - Expires 29 Oct 2026"])
    expect(resetCreditsView(credits, later).available).toBe(0)
    expect(resetCreditsView(credits, later).entries).toEqual([])
  })

  test("inventory errors do not blank usage or invent a zero count", async () => {
    for (const status of [401, 403, 429, 500]) {
      const result = await fetchUsage("codex", signal(), { credentials, fetch: async (url) =>
        url.endsWith("/usage") ? Response.json(usage) : new Response("private-error", { status }),
      })
      expect(result.windows[0].used).toBe(2)
      expect(result.resetCredits).toBeUndefined()
      expect(JSON.stringify(result)).not.toContain("private-error")
      if (status === 429) expect(result.resetCreditsRetryAt).toBeGreaterThan(Date.now() + 290_000)
    }
  })

  test("previous inventory survives failure and inventory backoff does not block ordinary usage", async () => {
    const previous = { available: 2, fetchedAt: now }
    const result = await fetchUsage("codex", signal(), { credentials, resetCredits: previous, fetch: async (url) =>
      url.endsWith("/usage") ? Response.json(usage)
        : new Response("", { status: 429, headers: { "retry-after": "600" } }),
    })
    expect(result.resetCredits).toEqual(previous)
    expect(result.resetCreditsRetryAt).toBeGreaterThan(Date.now() + 590_000)
    let requests = 0
    const cached = await fetchUsage("codex", signal(), { credentials,
      resetCredits: result.resetCredits, resetCreditsRetryAt: result.resetCreditsRetryAt,
      fetch: async () => { requests++; return Response.json(usage) },
    })
    expect(requests).toBe(1)
    expect(cached.windows[0].used).toBe(2)
    expect(cached.resetCredits).toEqual(previous)
    expect(cached.resetCreditsRetryAt).toBe(result.resetCreditsRetryAt)
  })

  test("successfully reading zero replaces the previous count and clears an expired cooldown", async () => {
    const result = await fetchUsage("codex", signal(), { credentials,
      resetCredits: { available: 2, fetchedAt: now }, resetCreditsRetryAt: Date.now() - 1,
      fetch: async (url) => Response.json(url.endsWith("/usage") ? usage : { available_count: 0 }),
    })
    expect(result.resetCredits?.available).toBe(0)
    expect(result.resetCreditsRetryAt).toBeUndefined()
  })

  test("malformed inventory and transport failures retain the last count without renewing its age", async () => {
    const previous = { available: 2, fetchedAt: now }
    for (const malformed of [true, false]) {
      const result = await fetchUsage("codex", signal(), { credentials, resetCredits: previous,
        fetch: async (url) => {
          if (url.endsWith("/usage")) return Response.json(usage)
          if (malformed) return Response.json({ available_count: "2" })
          throw new Error("private-network-error")
        },
      })
      expect(result.resetCredits).toEqual(previous)
      expect(result.windows[0].used).toBe(2)
    }
  })
})

describe("refresh lifecycle", () => {
  test("cached readings replace refresh errors with a quiet age note", () => {
    const cached = { snapshot, loading: false, error: "Rate limited", retryAt: now + 900_000 }
    expect(providerNotice(cached, now + 12 * 60_000)).toBe("Updated 12m ago")
    expect(providerNotice({ ...cached, error: "Offline / request timed out" }, now + 90 * 60_000)).toBe("Updated 1h 30m ago")
    expect(providerNotice(cached, now + 1500 * 60_000)).toBe("Updated 1d 1h ago")
    expect(providerNotice(cached, now)).toBe("Updated just now")
    expect(providerNotice(cached, now - 60_000)).toBe("Updated just now")
    expect(isStale(cached, now)).toBe(true)
  })

  test("fresh cached readings have no note; old readings show age even without an error", () => {
    const cached = { snapshot, loading: false }
    expect(providerNotice(cached, now)).toBeUndefined()
    expect(providerNotice(cached, now + 300_000)).toBeUndefined()
    expect(providerNotice(cached, now + 360_000)).toBe("Updated 6m ago")
    expect(isStale(cached, now)).toBe(false)
    expect(isStale(cached, now + 360_000)).toBe(true)
  })

  test("errors and inline retry countdowns remain visible when there is no reading", () => {
    expect(providerNotice({ loading: false, error: "Rate limited", retryAt: now + 60_000 }, now))
      .toBe("Rate Limited (Retrying in 1m)")
    expect(providerNotice({ loading: false, error: "Rate limited", retryAt: now }, now)).toBe("Rate Limited")
    expect(providerNotice({ loading: false, error: "Refresh login" }, now)).toBe("Refresh login")
    expect(providerNotice({ loading: true }, now)).toBeUndefined()
  })

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

  test("network errors retain stale data and auth errors clear it", async () => {
    let failure: UsageError | undefined
    let calls = 0
    const seen: Partial<Record<Provider, State>> = {}
    const monitor = createMonitor((provider, state) => { seen[provider] = state }, async () => {
      calls++
      if (failure) throw failure
      return snapshot
    })
    await monitor.refresh()
    failure = new UsageError("Rate limited", now + 300_000)
    await monitor.refresh()
    expect(seen.claude?.snapshot).toBe(snapshot)
    expect(seen.claude?.error).toBe("Rate limited")
    expect(calls).toBe(4)
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
