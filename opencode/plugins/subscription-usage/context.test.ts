import { describe, expect, test } from "bun:test"
import type { SessionMessageAssistant, SessionMessageInfo } from "@opencode/client"
import { contextUsage } from "./context"

const model = { providerID: "fixture-provider", id: "fixture-model" }
const models = [{ ...model, limit: { context: 1000, output: 200 } }]
function assistant(id: string, input = 20): SessionMessageAssistant {
  return { id, type: "assistant", time: { created: 0 }, agent: "build", model, content: [],
    tokens: { input, output: 10, reasoning: 5, cache: { read: 30, write: 35 } },
  }
}
const compaction: SessionMessageInfo = { id: "compacted", type: "compaction", status: "completed",
  time: { created: 0 }, reason: "manual", summary: "fixture", recent: "fixture",
}

describe("built-in Context parity", () => {
  test("uses the latest reported assistant tokens, including reasoning and both caches", () => {
    expect(contextUsage([assistant("first", 500), assistant("last")], models)).toEqual({ tokens: 100, percent: 10 })
    const streaming = { ...assistant("streaming"), tokens: undefined }
    expect(contextUsage([assistant("last"), streaming], models)).toEqual({ tokens: 100, percent: 10 })
  })

  test("missing/unknown model limits still show tokens, but no fabricated percentage", () => {
    expect(contextUsage([assistant("last")])).toEqual({ tokens: 100, percent: undefined })
    expect(contextUsage([assistant("last")], [{ ...models[0], providerID: "different" }])?.percent).toBeUndefined()
    expect(contextUsage([assistant("last")], [{ ...models[0], limit: { context: 0, output: 200 } }])?.percent).toBeUndefined()
  })

  test("empty sessions and zero-token latest readings do not show usage", () => {
    expect(contextUsage([])).toBeUndefined()
    const empty = { ...assistant("zero"), tokens: { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } } }
    expect(contextUsage([assistant("first"), empty], models)).toBeUndefined()
  })

  test("completed compaction clears old usage until a subsequent reported response", () => {
    expect(contextUsage([assistant("old"), compaction], models)).toBeUndefined()
    expect(contextUsage([assistant("old"), compaction, assistant("new")], models)).toEqual({ tokens: 100, percent: 10 })
    const running: SessionMessageInfo = { id: "running", type: "compaction", status: "running", reason: "manual", time: { created: 0 }, summary: "", recent: "" }
    expect(contextUsage([assistant("last"), running], models)).toEqual({ tokens: 100, percent: 10 })
  })

  test("undo excludes its boundary and later messages, including later compactions", () => {
    const messages = [assistant("kept"), assistant("undo", 900), compaction, assistant("later", 500)]
    expect(contextUsage(messages, models, "undo")).toEqual({ tokens: 100, percent: 10 })
    expect(contextUsage(messages, models, "kept")).toBeUndefined()
    expect(contextUsage(messages, models, "not-loaded")).toBeUndefined()
  })
})
