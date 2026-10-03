import { execFile } from "node:child_process"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { promisify } from "node:util"

export const providers = ["claude", "codex"] as const
export type Provider = (typeof providers)[number]
export type Window = { label: string; used: number; resetsAt?: number }
export type Snapshot = { windows: Window[]; fetchedAt: number; plan?: string }
export type State = { snapshot?: Snapshot; error?: string; retryAt?: number; loading: boolean }
type Credential = { token: string; accountID?: string; plan?: string }

const exec = promisify(execFile)
const endpoints = {
  claude: "https://api.anthropic.com/api/oauth/usage",
  codex: "https://chatgpt.com/backend-api/wham/usage",
}

export class UsageError extends Error {
  constructor(message: string, readonly retryAt?: number, readonly auth = false) {
    super(message)
  }
}

function object(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {}
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined
}

function number(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined
}

function window(label: string, used: unknown, reset: unknown): Window | undefined {
  const percent = number(used)
  if (percent === undefined) return
  const date = typeof reset === "string" ? Date.parse(reset) : Number.NaN
  return {
    label,
    used: Math.max(0, Math.min(100, percent)),
    resetsAt: Number.isFinite(date) ? date : undefined,
  }
}

export function parseClaude(value: unknown, now = Date.now()): Snapshot {
  const data = object(value)
  const windows: Window[] = []
  const add = (label: string, entry: unknown) => {
    const item = object(entry)
    const parsed = window(label, item.utilization, item.resets_at)
    if (parsed) windows.push(parsed)
  }
  add("5h", data.five_hour)
  add("Week", data.seven_day)

  // New Claude responses put model-specific weekly limits in this array.
  for (const entry of Array.isArray(data.limits) ? data.limits : []) {
    const item = object(entry)
    const model = object(object(item.scope).model)
    const label = item.kind === "session" ? "5h"
      : item.kind === "weekly_all" ? "Week"
      : text(model.display_name) ?? text(model.id)
    if (!label || windows.some((w) => w.label === label)) continue
    const parsed = window(label, item.percent, item.resets_at)
    if (parsed) windows.push(parsed)
  }
  for (const [key, label] of [["seven_day_sonnet", "Sonnet"], ["seven_day_opus", "Opus"]]) {
    if (!windows.some((w) => w.label.toLowerCase().includes(label.toLowerCase()))) add(label, data[key])
  }
  if (!windows.length) throw new UsageError("Usage unavailable")
  return { windows, fetchedAt: now }
}

function durationLabel(seconds: unknown, fallback: string): string {
  const duration = number(seconds)
  if (!duration || duration < 0) return fallback
  if (duration === 604800) return "Week"
  if (duration % 86400 === 0) return `${duration / 86400}d`
  if (duration % 3600 === 0) return `${duration / 3600}h`
  return `${Math.ceil(duration / 60)}m`
}

export function parseCodex(value: unknown, now = Date.now()): Snapshot {
  const data = object(value)
  const windows: Window[] = []
  const add = (limits: unknown, prefix = "") => {
    const rate = object(limits)
    for (const [key, fallback] of [["primary_window", "Session"], ["secondary_window", "Week"]]) {
      const item = object(rate[key])
      const used = number(item.used_percent)
      if (used === undefined) continue
      const reset = number(item.reset_at)
      const after = number(item.reset_after_seconds)
      windows.push({
        label: `${prefix}${durationLabel(item.limit_window_seconds, fallback)}`,
        used: Math.max(0, Math.min(100, used)),
        resetsAt: reset !== undefined ? reset * 1000 : after !== undefined ? now + after * 1000 : undefined,
      })
    }
  }
  // A primary window can be weekly; never assume it is a five-hour limit.
  add(data.rate_limit)
  for (const entry of Array.isArray(data.additional_rate_limits) ? data.additional_rate_limits : []) {
    const item = object(entry)
    const label = text(item.limit_name) ?? text(item.metered_feature)
    if (label) add(item.rate_limit, `${label} `)
  }
  if (!windows.length) throw new UsageError("Usage unavailable")
  return { windows, fetchedAt: now, plan: text(data.plan_type) }
}

async function jsonFile(path: string): Promise<Record<string, unknown> | undefined> {
  try {
    return object(JSON.parse(await readFile(path, "utf8")))
  } catch {
    return undefined
  }
}

export async function loadCredential(
  provider: Provider,
  signal: AbortSignal,
  env: NodeJS.ProcessEnv = process.env,
  home = homedir(),
): Promise<Credential> {
  signal.throwIfAborted()
  if (provider === "codex") {
    const data = await jsonFile(join(env.CODEX_HOME || join(home, ".codex"), "auth.json"))
    const tokens = object(data?.tokens)
    const token = text(tokens.access_token)
    if (!token) throw new UsageError("Sign in with codex login", undefined, true)
    let claims: Record<string, unknown> = {}
    try {
      claims = object(JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString()))
    } catch { /* Opaque tokens are valid too; the API checks authentication. */ }
    return {
      token,
      accountID: text(tokens.account_id) ?? text(object(claims["https://api.openai.com/auth"]).chatgpt_account_id),
    }
  }

  let data: Record<string, unknown> | undefined
  // The default macOS login lives in Keychain. A custom config directory must
  // never silently use the default account's Keychain credentials.
  if (process.platform === "darwin" && !env.CLAUDE_CONFIG_DIR) {
    try {
      const { stdout } = await exec("/usr/bin/security", [
        "find-generic-password", "-s", "Claude Code-credentials", "-w",
      ], { encoding: "utf8", timeout: 5000, signal, maxBuffer: 1024 * 1024 })
      data = object(JSON.parse(stdout))
    } catch { /* Fall back to Claude Code's file-based credential store. */ }
  }
  if (!text(object(data?.claudeAiOauth).accessToken)) {
    data = await jsonFile(join(env.CLAUDE_CONFIG_DIR || join(home, ".claude"), ".credentials.json"))
  }
  signal.throwIfAborted()
  const oauth = object(data?.claudeAiOauth)
  const token = text(oauth.accessToken)
  if (!token) throw new UsageError("Sign in with claude auth login", undefined, true)
  return { token, plan: text(oauth.subscriptionType) }
}

export function retryAfter(value: string | null, now = Date.now()): number {
  const seconds = value?.trim() ? Number(value) : Number.NaN
  const date = value ? Date.parse(value) : Number.NaN
  const until = Number.isFinite(seconds) ? now + Math.max(0, seconds) * 1000 : date
  return Number.isFinite(until) ? Math.max(now + 60_000, until) : now + 300_000
}

export async function fetchUsage(
  provider: Provider,
  signal: AbortSignal,
  dependencies: {
    credentials: typeof loadCredential
    fetch: (url: string, init: RequestInit) => Promise<Response>
  } = { credentials: loadCredential, fetch: globalThis.fetch },
): Promise<Snapshot> {
  const credential = await dependencies.credentials(provider, signal)
  const headers: Record<string, string> = {
    Authorization: `Bearer ${credential.token}`,
    Accept: "application/json",
    "User-Agent": "opencode-subscription-usage/0.1.0",
  }
  if (provider === "claude") headers["anthropic-beta"] = "oauth-2025-04-20"
  if (provider === "codex" && credential.accountID) headers["ChatGPT-Account-Id"] = credential.accountID
  let response: Response
  try {
    response = await dependencies.fetch(endpoints[provider], {
      headers,
      signal: AbortSignal.any([signal, AbortSignal.timeout(10_000)]),
      redirect: "error",
    })
  } catch {
    signal.throwIfAborted()
    throw new UsageError("Offline / request timed out")
  }
  if (response.status === 401) {
    throw new UsageError(`Open ${provider === "claude" ? "Claude Code" : "Codex"} to refresh login`, undefined, true)
  }
  if (response.status === 429) throw new UsageError("Rate limited", retryAfter(response.headers.get("retry-after")))
  if (!response.ok) throw new UsageError(`Usage API: HTTP ${response.status}`)
  let data: unknown
  try {
    data = await response.json()
  } catch {
    throw new UsageError("Invalid usage response")
  }
  const snapshot = provider === "claude" ? parseClaude(data) : parseCodex(data)
  return { ...snapshot, plan: snapshot.plan ?? credential.plan }
}

export function countdown(resetsAt: number | undefined, now: number): string {
  if (resetsAt === undefined) return "Reset time unavailable"
  if (resetsAt <= now) return "Reset due"
  const minutes = Math.ceil((resetsAt - now) / 60_000)
  if (minutes >= 1440) return `${Math.floor(minutes / 1440)}d ${Math.floor((minutes % 1440) / 60)}h`
  if (minutes >= 60) return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
  return `${minutes}m`
}

export function createMonitor(
  change: (provider: Provider, state: State) => void,
  load: (provider: Provider, signal: AbortSignal) => Promise<Snapshot | State>,
) {
  const controller = new AbortController()
  const state: Record<Provider, State> = { claude: { loading: true }, codex: { loading: true } }
  const pending = new Map<Provider, Promise<void>>()
  let timer: ReturnType<typeof setInterval> | undefined

  const refreshOne = (provider: Provider): Promise<void> => {
    const inflight = pending.get(provider)
    if (inflight) return inflight
    if (controller.signal.aborted) return Promise.resolve()
    state[provider] = { ...state[provider], loading: true }
    change(provider, state[provider])
    const request = (async () => {
      try {
        const result = await load(provider, controller.signal)
        if (controller.signal.aborted) return
        state[provider] = "loading" in result ? result : { snapshot: result, loading: false }
      } catch (error) {
        if (controller.signal.aborted) return
        const failure = error instanceof UsageError ? error : new UsageError("Usage unavailable")
        state[provider] = {
          snapshot: failure.auth ? undefined : state[provider].snapshot,
          error: failure.message,
          retryAt: failure.retryAt,
          loading: false,
        }
      }
      change(provider, state[provider])
    })().finally(() => pending.delete(provider))
    pending.set(provider, request)
    return request
  }

  const refresh = async () => { await Promise.all(providers.map(refreshOne)) }
  return {
    refresh,
    start(interval = 120_000) {
      if (timer || controller.signal.aborted) return
      void refresh()
      timer = setInterval(() => void refresh(), interval)
    },
    stop() {
      clearInterval(timer)
      controller.abort()
    },
  }
}
