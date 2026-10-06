import { describe, expect, test } from "bun:test"
import type { OpenCodeClient } from "@opencode/client"
import { cmuxTarget, createCmuxSync, vcsReader } from "./cmux"

const target = {
  workspace_id: "11111111-1111-1111-1111-111111111111",
  surface_id: "22222222-2222-2222-2222-222222222222",
}
type Call = { method: string; params: Record<string, unknown> }

function fixture(read: Parameters<typeof createCmuxSync>[0]["read"] = async (directory) => ({ branch: directory === "/repo" ? "main" : "feature", dirty: false })) {
  const calls: Call[] = []
  const sync = createCmuxSync({
    target, read,
    rpc: async (method, params) => { calls.push({ method, params }) },
  })
  return { calls, sync }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((done) => { resolve = done })
  return { promise, resolve }
}

describe("cmux checkout synchronization", () => {
  test("requires both exact terminal IDs; never targets the selected surface", () => {
    expect(cmuxTarget({})).toBeUndefined()
    expect(cmuxTarget({ CMUX_WORKSPACE_ID: target.workspace_id })).toBeUndefined()
    expect(cmuxTarget({ CMUX_WORKSPACE_ID: "workspace:1", CMUX_SURFACE_ID: target.surface_id })).toBeUndefined()
    expect(cmuxTarget({ CMUX_WORKSPACE_ID: target.workspace_id, CMUX_SURFACE_ID: target.surface_id })).toEqual(target)
  })

  test("moves the same session from main to a worktree, with scoped cwd/branch reports", async () => {
    const { sync, calls } = fixture()
    try {
      sync.update("/repo")
      await sync.refresh()
      expect(calls[0]).toEqual({ method: "surface.clear_git_branch", params: target })
      expect(calls[1]).toEqual({ method: "surface.report_pwd", params: { ...target, path: "/repo" } })
      expect(calls.at(-1)).toEqual({ method: "surface.report_git_branch", params: { ...target, branch: "main", is_dirty: false } })
      calls.length = 0
      sync.update("/worktree with 'quotes'")
      await sync.refresh()
      expect(calls[0].method).toBe("surface.clear_git_branch")
      expect(calls[1].params.path).toBe("/worktree with 'quotes'")
      expect(calls.at(-1)?.params.branch).toBe("feature")
      expect(calls.every(({ params }) => params.workspace_id === target.workspace_id && params.surface_id === target.surface_id)).toBe(true)
    } finally { sync.stop() }
  })

  test("refreshes branch and dirtiness without changing cwd; clears non-repositories", async () => {
    let branch: string | undefined = "feature"
    let dirty = false
    const { sync, calls } = fixture(async () => ({ branch, dirty }))
    try {
      sync.update("/repo")
      await sync.refresh()
      calls.length = 0
      branch = "renamed"; dirty = true
      await sync.refresh()
      expect(calls).toEqual([{ method: "surface.report_git_branch", params: { ...target, branch: "renamed", is_dirty: true } }])
      dirty = false
      await sync.refresh()
      expect(calls.at(-1)?.params.is_dirty).toBe(false)
      branch = undefined
      await sync.refresh()
      expect(calls.at(-1)?.method).toBe("surface.clear_git_branch")
    } finally { sync.stop() }
  })

  test("a slow old checkout cannot overwrite the newly displayed session", async () => {
    const old = deferred<{ branch: string; dirty: boolean }>()
    const entered = deferred<void>()
    const { sync, calls } = fixture(async (directory) => {
      if (directory === "/repo") { entered.resolve(); return old.promise }
      return { branch: "new-session", dirty: true }
    })
    try {
      sync.update("/repo")
      await entered.promise
      sync.update("/other")
      old.resolve({ branch: "stale-main", dirty: false })
      await sync.refresh()
      expect(calls.some(({ params }) => params.branch === "stale-main")).toBe(false)
      expect(calls.at(-1)?.params.branch).toBe("new-session")
    } finally { sync.stop() }
  })

  test("no updates after unload, including a read that finishes late", async () => {
    const read = deferred<{ branch: string; dirty: boolean }>()
    const entered = deferred<void>()
    const { sync, calls } = fixture(async () => { entered.resolve(); return read.promise })
    sync.update("/repo")
    await entered.promise
    sync.stop()
    const count = calls.length
    read.resolve({ branch: "too-late", dirty: true })
    await sync.refresh()
    await Bun.sleep(0)
    sync.update("/other")
    expect(calls).toHaveLength(count)
  })

  test("failed reads do not retain main in a new checkout; failures retry quietly", async () => {
    const calls: Call[] = []
    let failures = true
    let warnings = 0
    const sync = createCmuxSync({
      target,
      read: async () => { if (failures) throw new Error("offline"); return { branch: "recovered", dirty: false } },
      rpc: async (method, params) => { calls.push({ method, params }) },
      warn: () => { warnings++ },
    })
    try {
      sync.update("/worktree")
      await sync.refresh()
      await sync.refresh()
      expect(warnings).toBe(1)
      expect(calls.some(({ method }) => method === "surface.report_git_branch")).toBe(false)
      expect(calls[0].method).toBe("surface.clear_git_branch")
      failures = false
      await sync.refresh()
      expect(calls.at(-1)?.params.branch).toBe("recovered")
    } finally { sync.stop() }
  })

  test("periodic refresh picks up edits and stops on cleanup", async () => {
    let reads = 0
    const refreshed = deferred<void>()
    const sync = createCmuxSync({
      target, interval: 10,
      read: async () => { if (++reads >= 2) refreshed.resolve(); return { branch: "feature", dirty: reads > 1 } },
      rpc: async () => {},
    })
    try {
      sync.update("/repo")
      await refreshed.promise
      sync.stop()
      const count = reads
      await Bun.sleep(30)
      expect(reads).toBe(count)
    } finally { sync.stop() }
  })

  test("reads VCS at the requested server location, not the launch directory", async () => {
    const directories: string[] = []
    const client = { vcs: {
      get: async ({ location }: { location: { directory: string } }) => {
        directories.push(location.directory)
        return { data: { branch: { current: "remote-feature" } } }
      },
      status: async ({ location }: { location: { directory: string } }) => {
        directories.push(location.directory)
        return { data: [{ path: "changed.ts" }] }
      },
    } } as unknown as OpenCodeClient
    expect(await vcsReader(client)("/remote/worktree", new AbortController().signal)).toEqual({ branch: "remote-feature", dirty: true })
    expect(directories).toEqual(["/remote/worktree", "/remote/worktree"])
  })
})
