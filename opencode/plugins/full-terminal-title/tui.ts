import { Plugin } from "@opencode/plugin/tui"
import { createEffect, onCleanup } from "solid-js"
import { terminalTitle } from "./title"
import { cmuxTarget, createCmuxSync, vcsReader } from "./cmux"

export default Plugin.define({
  id: "calum.full-terminal-title",
  setup(context) {
    // The mounted app slot owns the effect, so plugin reload/unload disposes it.
    // Disable the built-in writer with terminal.title=false to avoid two writers.
    return context.ui.slot({
      append: "app",
      render: () => {
        const target = cmuxTarget(process.env)
        const sync = target ? createCmuxSync({
          target,
          read: vcsReader(context.client),
          warn: () => context.ui.toast.show({
            message: "Could not sync OpenCode's checkout to cmux; will retry.",
            variant: "warning",
          }),
        }) : undefined
        onCleanup(() => sync?.stop())
        createEffect(() => {
          const route = context.ui.router.current()
          const session = route.type === "session" ? context.data.session.get(route.sessionID) : undefined
          if (!context.renderer.isDestroyed) {
            context.renderer.setTerminalTitle(terminalTitle(route, session?.title))
            // Wait for a session to load rather than briefly reporting main.
            // Home/plugin pages return to the CLI's original launch location.
            sync?.update(route.type === "session" ? session?.location?.directory : context.location?.directory)
          }
        })
        return null
      },
    })
  },
})
