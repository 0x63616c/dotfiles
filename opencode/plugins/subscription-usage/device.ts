import { Database } from "bun:sqlite"
import { createHash, randomUUID } from "node:crypto"
import { chmod, mkdir } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { setTimeout as sleep } from "node:timers/promises"
import { fetchUsage, loadCredential, UsageError, type Provider, type Snapshot, type State } from "./usage"

type Entry = {
  snapshot?: Snapshot
  error?: string
  retryAt?: number
  nextAttemptAt: number
  rateLimits: number
  owner?: { pid: number; id: string }
}
type Claim = { kind: "waiting" } | { kind: "cached"; state: State } | { kind: "owned"; previous: Entry }

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return (error as NodeJS.ErrnoException).code !== "ESRCH"
  }
}

function view(entry: Entry): State {
  return { snapshot: entry.snapshot, error: entry.error, retryAt: entry.retryAt, loading: false }
}

/** One durable request budget per device/login, shared by independent CLI processes. */
export function createDeviceUsage(options: {
  directory?: string
  interval?: number
  credentials?: typeof loadCredential
  fetch?: typeof fetchUsage
  now?: () => number
} = {}) {
  const directory = options.directory ?? join(process.env.XDG_CACHE_HOME || join(homedir(), ".cache"), "opencode", "subscription-usage")
  const interval = Math.max(60_000, options.interval ?? 120_000)
  const credentials = options.credentials ?? loadCredential
  const fetch = options.fetch ?? fetchUsage
  const now = options.now ?? Date.now

  return async (provider: Provider, signal: AbortSignal): Promise<State> => {
    const credential = await credentials(provider, signal)
    signal.throwIfAborted()
    // No credentials are persisted. Different accounts/profiles never see each
    // other's readings, while identical logins share the same request budget.
    const key = `${provider}:${createHash("sha256").update(JSON.stringify([credential.token, credential.accountID])).digest("hex")}`
    let opened: Database | undefined
    try {
      await mkdir(directory, { recursive: true, mode: 0o700 })
      await chmod(directory, 0o700)
      opened = new Database(join(directory, "usage.sqlite"), { create: true })
      await chmod(join(directory, "usage.sqlite"), 0o600)
      opened.exec("PRAGMA busy_timeout = 5000")
      opened.exec("CREATE TABLE IF NOT EXISTS usage (key TEXT PRIMARY KEY, entry TEXT NOT NULL)")
    } catch {
      opened?.close()
      // Fail closed: falling back to an independent poller would recreate the bug.
      throw new UsageError("Device usage cache unavailable")
    }
    const db = opened

    const read = () => {
      const row = db.query<{ entry: string }, [string]>("SELECT entry FROM usage WHERE key = ?").get(key)
      return row ? JSON.parse(row.entry) as Entry : { nextAttemptAt: 0, rateLimits: 0 }
    }
    const write = (entry: Entry) => {
      db.query("INSERT INTO usage (key, entry) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET entry = excluded.entry")
        .run(key, JSON.stringify(entry))
    }
    const id = randomUUID()
    let previous: Entry
    try {
      while (true) {
        signal.throwIfAborted()
        // SQLite's cross-process write lock makes checking the budget and taking
        // ownership one atomic operation — including simultaneous TUI startups.
        const claim = db.transaction((): Claim => {
          const entry = read()
          if (entry.owner && alive(entry.owner.pid)) return { kind: "waiting" }
          if (entry.owner) {
            delete entry.owner
            entry.error ??= "Refresh interrupted"
            write(entry)
          }
          if (entry.nextAttemptAt > now()) return { kind: "cached", state: view(entry) }
          write({ ...entry, nextAttemptAt: now() + interval, owner: { pid: process.pid, id } })
          return { kind: "owned", previous: entry }
        }).immediate()
        if (claim.kind === "cached") return claim.state
        if (claim.kind === "owned") {
          previous = claim.previous
          break
        }
        await sleep(100, undefined, { signal })
      }

      let entry: Entry
      try {
        const snapshot = await fetch(provider, signal, {
          credentials: async () => credential,
          fetch: globalThis.fetch,
        })
        signal.throwIfAborted()
        entry = { snapshot, nextAttemptAt: now() + interval, rateLimits: 0 }
      } catch (error) {
        signal.throwIfAborted()
        const failure = error instanceof UsageError ? error : new UsageError("Usage unavailable")
        const rateLimits = failure.message === "Rate limited" ? previous.rateLimits + 1 : 0
        // A missing/zero Retry-After is not evidence that the limit has reset.
        // Repeated 429s progressively back off, up to 30 minutes, device-wide.
        const retryAt = rateLimits ? Math.max(failure.retryAt ?? 0,
          now() + Math.min(1_800_000, 300_000 * 2 ** Math.min(rateLimits - 1, 3))) : failure.retryAt
        entry = {
          snapshot: failure.auth ? undefined : previous.snapshot,
          error: failure.message,
          retryAt,
          nextAttemptAt: Math.max(now() + interval, retryAt ?? 0),
          rateLimits,
        }
      }
      db.transaction(() => {
        if (read().owner?.id === id) write(entry)
      }).immediate()
      return view(entry)
    } finally {
      try {
        // Cancellation releases ownership, but keeps the reserved request budget.
        // A killed process is recovered by the next reader using its dead PID.
        db.transaction(() => {
          const entry = read()
          if (entry.owner?.id !== id) return
          delete entry.owner
          entry.error ??= "Refresh interrupted"
          write(entry)
        }).immediate()
      } finally {
        db.close()
      }
    }
  }
}
