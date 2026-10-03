import { Database } from "bun:sqlite"
import { describe, expect, test } from "bun:test"
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { setTimeout as sleep } from "node:timers/promises"
import { createDeviceUsage } from "./device"
import { UsageError, type Snapshot } from "./usage"

const now = Date.parse("2026-10-02T12:00:00Z")
const snapshot: Snapshot = { fetchedAt: now, windows: [{ label: "Week", used: 29 }] }
const signal = () => new AbortController().signal
const credentials = async () => ({ token: "fixture-secret", accountID: "fixture-account" })

async function temporary(run: (directory: string) => Promise<void>) {
  const directory = await mkdtemp(join(tmpdir(), "opencode-device-usage-test-"))
  try {
    await run(directory)
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
}

describe("device-wide usage budget", () => {
  test("simultaneous instances share one fetch and cached startup/manual refreshes", () => temporary(async (directory) => {
    let calls = 0
    const fetch = async () => {
      calls++
      await sleep(50)
      return snapshot
    }
    const instance = () => createDeviceUsage({ directory, credentials, fetch, now: () => now })
    const states = await Promise.all(Array.from({ length: 12 }, () => instance()("claude", signal())))
    expect(calls).toBe(1)
    expect(states.every((state) => state.snapshot?.windows[0].used === 29)).toBe(true)
    await instance()("claude", signal())
    expect(calls).toBe(1)
    expect((await stat(directory)).mode & 0o777).toBe(0o700)
    expect((await stat(join(directory, "usage.sqlite"))).mode & 0o777).toBe(0o600)
    expect((await readFile(join(directory, "usage.sqlite"))).includes(Buffer.from("fixture-secret"))).toBe(false)
  }))

  test("rate-limit cooldown persists across restarts and backs off 5 → 10 → 20 → 30 minutes", () => temporary(async (directory) => {
    let time = now
    let calls = 0
    const fetch = async () => {
      calls++
      throw new UsageError("Rate limited", time + 60_000)
    }
    const instance = () => createDeviceUsage({ directory, credentials, fetch, now: () => time })
    for (const minutes of [5, 10, 20, 30, 30]) {
      const state = await instance()("claude", signal())
      expect(state.error).toBe("Rate limited")
      expect(state.retryAt).toBe(time + minutes * 60_000)
      const count = calls
      expect(await instance()("claude", signal())).toEqual(state)
      expect(calls).toBe(count)
      time = state.retryAt!
    }
    expect(calls).toBe(5)
  }))

  test("server Retry-After wins over the fallback cooldown", () => temporary(async (directory) => {
    const load = createDeviceUsage({ directory, credentials, now: () => now,
      fetch: async () => { throw new UsageError("Rate limited", now + 3_600_000) },
    })
    expect((await load("claude", signal())).retryAt).toBe(now + 3_600_000)
  }))

  test("all instances see the same polling boundary and success resets the next budget", () => temporary(async (directory) => {
    let time = now
    let calls = 0
    const instance = () => createDeviceUsage({ directory, credentials, now: () => time,
      fetch: async () => { calls++; await sleep(20); return { ...snapshot, fetchedAt: time } },
    })
    await instance()("codex", signal())
    time += 119_999
    await Promise.all(Array.from({ length: 5 }, () => instance()("codex", signal())))
    expect(calls).toBe(1)
    time++
    await Promise.all(Array.from({ length: 5 }, () => instance()("codex", signal())))
    expect(calls).toBe(2)
  }))

  test("cancelled waiters do not release another instance's ownership", () => temporary(async (directory) => {
    let calls = 0
    let release!: (value: Snapshot) => void
    let started!: () => void
    const ready = new Promise<void>((resolve) => { started = resolve })
    const instance = () => createDeviceUsage({ directory, credentials, now: () => now,
      fetch: async () => {
        calls++
        started()
        return new Promise<Snapshot>((resolve) => { release = resolve })
      },
    })
    const owner = instance()("claude", signal())
    await ready
    const controller = new AbortController()
    const waiter = instance()("claude", controller.signal)
    await sleep(20)
    controller.abort()
    await expect(waiter).rejects.toThrow()
    const other = instance()("claude", signal())
    await sleep(20)
    expect(calls).toBe(1)
    release(snapshot)
    expect((await owner).snapshot).toEqual(snapshot)
    expect((await other).snapshot).toEqual(snapshot)
  }))

  test("cancelled owners release the claim but preserve the device's request budget", () => temporary(async (directory) => {
    let calls = 0
    const controller = new AbortController()
    const owner = createDeviceUsage({ directory, credentials, now: () => now,
      fetch: async () => { calls++; controller.abort(); throw controller.signal.reason },
    })
    await expect(owner("claude", controller.signal)).rejects.toThrow()
    const next = createDeviceUsage({ directory, credentials, now: () => now,
      fetch: async () => { calls++; return snapshot },
    })
    expect((await next("claude", signal())).error).toBe("Refresh interrupted")
    expect(calls).toBe(1)
  }))

  test("stale readings and errors are shared; recovery resets the backoff; auth clears readings", () => temporary(async (directory) => {
    let time = now
    let failure: UsageError | undefined
    let calls = 0
    const fetch = async () => {
      calls++
      if (failure) throw failure
      return snapshot
    }
    const instance = () => createDeviceUsage({ directory, credentials, fetch, now: () => time })
    await instance()("claude", signal())
    time += 120_000
    failure = new UsageError("Rate limited")
    const stale = await instance()("claude", signal())
    expect(stale.snapshot).toEqual(snapshot)
    expect(await instance()("claude", signal())).toEqual(stale)
    expect(calls).toBe(2)
    time = stale.retryAt!
    failure = undefined
    expect((await instance()("claude", signal())).error).toBeUndefined()
    time += 120_000
    failure = new UsageError("Rate limited")
    expect((await instance()("claude", signal())).retryAt).toBe(time + 300_000)
    time += 300_000
    failure = new UsageError("Refresh login", undefined, true)
    expect((await instance()("claude", signal())).snapshot).toBeUndefined()
    expect((await instance()("claude", signal())).snapshot).toBeUndefined()
  }))

  test("providers and different logins do not share readings or block each other", () => temporary(async (directory) => {
    let calls = 0
    const fetch = async () => { calls++; return snapshot }
    const a = createDeviceUsage({ directory, credentials, fetch, now: () => now })
    const b = createDeviceUsage({ directory, fetch, now: () => now,
      credentials: async () => ({ token: "another-profile" }),
    })
    await Promise.all([a("claude", signal()), a("codex", signal()), b("claude", signal())])
    expect(calls).toBe(3)
    await Promise.all([a("claude", signal()), a("codex", signal()), b("claude", signal())])
    expect(calls).toBe(3)
  }))

  test("cache failures fail closed instead of starting an independent poller", () => temporary(async (directory) => {
    const path = join(directory, "not-a-directory")
    await writeFile(path, "fixture")
    let calls = 0
    const load = createDeviceUsage({ directory: path, credentials,
      fetch: async () => { calls++; return snapshot },
    })
    await expect(load("claude", signal())).rejects.toThrow("Device usage cache unavailable")
    expect(calls).toBe(0)
  }))

  test("independent OS processes racing at startup make exactly one provider request", () => temporary(async (directory) => {
    const log = join(directory, "requests")
    const script = `
      import { appendFile } from "node:fs/promises"
      import { createDeviceUsage } from ${JSON.stringify(new URL("./device.ts", import.meta.url).href)}
      const load = createDeviceUsage({
        directory: ${JSON.stringify(directory)},
        credentials: async () => ({ token: "process-fixture" }),
        fetch: async () => {
          await appendFile(${JSON.stringify(log)}, "request\\n")
          await Bun.sleep(200)
          return ${JSON.stringify(snapshot)}
        }
      })
      const state = await load("claude", new AbortController().signal)
      if (state.snapshot?.windows[0].used !== 29) process.exit(1)
    `
    const children = Array.from({ length: 8 }, () => Bun.spawn([process.execPath, "--eval", script], {
      stdout: "pipe", stderr: "pipe",
    }))
    const results = await Promise.all(children.map(async (child) => ({
      exit: await child.exited, error: await new Response(child.stderr).text(),
    })))
    expect(results).toEqual(Array.from({ length: 8 }, () => ({ exit: 0, error: "" })))
    expect(await readFile(log, "utf8")).toBe("request\n")
  }))

  test("a killed owner is recovered without spending its reserved budget again", () => temporary(async (directory) => {
    const script = `
      import { createDeviceUsage } from ${JSON.stringify(new URL("./device.ts", import.meta.url).href)}
      const load = createDeviceUsage({
        directory: ${JSON.stringify(directory)}, now: () => ${now},
        credentials: async () => ({ token: "fixture-secret", accountID: "fixture-account" }),
        fetch: async () => { console.log("started"); await Bun.sleep(60000); return ${JSON.stringify(snapshot)} }
      })
      await load("claude", new AbortController().signal)
    `
    const child = Bun.spawn([process.execPath, "--eval", script], { stdout: "pipe", stderr: "pipe" })
    try {
      const output = await child.stdout.getReader().read()
      expect(new TextDecoder().decode(output.value)).toContain("started")
      child.kill()
      await child.exited
      let calls = 0
      let time = now
      const load = createDeviceUsage({ directory, credentials, now: () => time,
        fetch: async () => { calls++; return snapshot },
      })
      expect((await load("claude", signal())).error).toBe("Refresh interrupted")
      expect(calls).toBe(0)
      time += 120_000
      expect((await load("claude", signal())).snapshot).toEqual(snapshot)
      expect(calls).toBe(1)
      const db = new Database(join(directory, "usage.sqlite"))
      try {
        const row = db.query<{ entry: string }, []>("SELECT entry FROM usage").get()!
        expect(JSON.parse(row.entry).owner).toBeUndefined()
      } finally { db.close() }
    } finally {
      child.kill()
      await child.exited
    }
  }), 10_000)
})
