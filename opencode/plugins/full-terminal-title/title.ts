import type { Route } from "@opencode/plugin/tui/context"

const defaultTitle = /^(New session|Child session) - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

// No length limit: the terminal/sidebar decides how much fits. Keep control
// characters out of OSC titles, including BEL, ESC and C1 sequence delimiters.
export function terminalTitle(route: Route, title?: string): string {
  if (route.type === "home") return "OpenCode"
  if (route.type === "plugin") return `OC | ${safeTitle(route.name)}`
  if (!title?.trim() || defaultTitle.test(title)) return "OpenCode"
  return `OC | ${safeTitle(title)}`
}

function safeTitle(title: string): string {
  return title.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
}
