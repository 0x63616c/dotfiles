import { execFile } from "node:child_process"
import { promisify } from "node:util"
import type { OpenCodeClient } from "@opencode/client"

const exec = promisify(execFile)
type Target = { workspace_id: string; surface_id: string }
type Snapshot = { branch?: string; dirty: boolean }
type Rpc = (method: string, params: Record<string, unknown>, signal: AbortSignal) => Promise<void>

// Never fall back to cmux's selected workspace/surface. The background service
// can have another terminal's environment; only this CLI instance owns these IDs.
export function cmuxTarget(env: NodeJS.ProcessEnv): Target | undefined {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  const workspace_id = env.CMUX_WORKSPACE_ID ?? ""
  const surface_id = env.CMUX_SURFACE_ID ?? ""
  return uuid.test(workspace_id) && uuid.test(surface_id) ? { workspace_id, surface_id } : undefined
}

export const cmuxRpc: Rpc = async (method, params, signal) => {
  // argv, not shell interpolation: paths/branches may contain spaces or quotes.
  const { stdout } = await exec("cmux", ["rpc", method, JSON.stringify(params)], {
    signal, timeout: 3_000, maxBuffer: 1024 * 1024,
  })
  const reply = JSON.parse(stdout)
  if (reply.ok === false || reply.error) throw new Error(reply.error?.message ?? "cmux rejected metadata")
}

export function vcsReader(client: OpenCodeClient) {
  return async (directory: string, signal: AbortSignal): Promise<Snapshot> => {
    const options = { signal: AbortSignal.any([signal, AbortSignal.timeout(3_000)]) }
    // Query the session's location, never the plugin's launch location. Using
    // the connected server also avoids inspecting a same-named local checkout
    // when OpenCode is attached to a remote server.
    const info = await client.vcs.get({ location: { directory } }, options)
    const branch = info.data.branch.current || undefined
    if (!branch) return { dirty: false }
    const status = await client.vcs.status({ location: { directory } }, options)
    return { branch, dirty: status.data.length > 0 }
  }
}

export function createCmuxSync(options: {
  target: Target
  read: (directory: string, signal: AbortSignal) => Promise<Snapshot>
  rpc?: Rpc
  warn?: (error: unknown) => void
  interval?: number
}) {
  const rpc = options.rpc ?? cmuxRpc
  const controller = new AbortController()
  let directory: string | undefined
  let reportedDirectory: string | undefined
  let generation = 0
  let pending = false
  let running: Promise<void> | undefined
  let timer: ReturnType<typeof setInterval> | undefined
  let warned = false

  async function drain() {
    while (pending && !controller.signal.aborted) {
      pending = false
      const current = directory
      const version = generation
      if (!current) continue
      const active = () => !controller.signal.aborted && version === generation
      try {
        if (reportedDirectory !== current) {
          // A failed read of the new checkout must not leave a convincing but
          // wrong "main" label from the previous one.
          await rpc("surface.clear_git_branch", options.target, controller.signal)
          if (!active()) continue
          await rpc("surface.report_pwd", { ...options.target, path: current }, controller.signal)
          if (!active()) continue
          reportedDirectory = current
        }
        const snapshot = await options.read(current, controller.signal)
        if (!active()) continue
        if (snapshot.branch) {
          await rpc("surface.report_git_branch", {
            ...options.target, branch: snapshot.branch, is_dirty: snapshot.dirty,
          }, controller.signal)
        } else {
          await rpc("surface.clear_git_branch", options.target, controller.signal)
        }
        // Reassert branch on refresh: the parent shell's HEAD watcher can
        // otherwise overwrite it if the launch checkout changes in another pane.
        warned = false
      } catch (error) {
        if (active() && !warned) {
          warned = true
          options.warn?.(error)
        }
      }
    }
  }

  function refresh(): Promise<void> {
    if (controller.signal.aborted) return Promise.resolve()
    pending = true
    if (!running) running = drain().finally(() => { running = undefined })
    return running
  }

  return {
    update(next: string | undefined) {
      if (controller.signal.aborted || next === directory) return
      directory = next
      generation++
      if (!timer && next) timer = setInterval(() => void refresh(), options.interval ?? 5_000)
      void refresh()
    },
    refresh,
    stop() {
      if (timer) clearInterval(timer)
      controller.abort()
      pending = false
    },
  }
}
