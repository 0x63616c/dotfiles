import { expect, test } from "bun:test"
import { BoxRenderable, TextRenderable } from "@opentui/core"
import { createTestRenderer } from "@opentui/core/testing"

test("the usage bar fills remaining space and the reset stays right-aligned on resize", async () => {
  const test = await createTestRenderer({ width: 36, height: 3 })
  try {
    const row = new BoxRenderable(test.renderer, { width: "100%", flexDirection: "row", gap: 2 })
    const bar = new BoxRenderable(test.renderer, { width: 0, flexGrow: 1, minWidth: 0 })
    const line = new TextRenderable(test.renderer, { content: "─".repeat(20), wrapMode: "none" })
    bar.onSizeChange = function () { line.content = "─".repeat(this.width) }
    bar.add(line)
    row.add(bar)
    row.add(new TextRenderable(test.renderer, { content: "6d 20h", flexShrink: 0, wrapMode: "none" }))
    test.renderer.root.add(row)
    for (const width of [36, 30, 42]) {
      test.resize(width, 3)
      await test.flush()
      expect(bar.width).toBe(width - 8)
      expect(test.captureCharFrame().split("\n")[0]).toBe(`${"─".repeat(width - 8)}  6d 20h`)
    }
  } finally {
    test.renderer.destroy()
  }
})
