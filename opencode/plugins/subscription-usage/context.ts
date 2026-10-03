import type { ModelInfo, SessionMessageAssistant, SessionMessageInfo } from "@opencode/client"

/** Match OpenCode 2.0.22's Context section, including compaction/undo boundaries. */
export function contextUsage(
  messages: readonly SessionMessageInfo[],
  models?: readonly Pick<ModelInfo, "providerID" | "id" | "limit">[],
  revertMessageID?: string,
): { tokens: number; percent?: number } | undefined {
  const reverted = revertMessageID ? messages.findIndex((message) => message.id === revertMessageID) : -1
  if (revertMessageID && reverted === -1) return
  const end = reverted === -1 ? messages.length : reverted
  const compacted = messages.findLastIndex((message, index) =>
    message.type === "compaction" && message.status === "completed" && index < end)
  const assistant = messages.findLast((message, index): message is SessionMessageAssistant =>
    message.type === "assistant" && message.tokens !== undefined && index > compacted && index < end)
  const usage = assistant?.tokens
  if (!assistant || !usage) return
  const tokens = usage.input + usage.output + usage.reasoning + usage.cache.read + usage.cache.write
  if (tokens <= 0) return
  const model = models?.find((model) => model.providerID === assistant.model.providerID && model.id === assistant.model.id)
  return { tokens, percent: model?.limit.context ? Math.round(tokens / model.limit.context * 100) : undefined }
}
