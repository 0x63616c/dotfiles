import type { Register } from 'claude-code'

const isOn = { plugin: 'simple-view', key: 'isOn' } as const
const STORED = 'isOn'

/** The spinner's word in the simple view: what the turn is doing, plainly. */
export function spinnerWord(mode: 'requesting' | 'responding' | 'thinking' | 'tool-input' | 'tool-use'): string {
  switch (mode) {
    case 'requesting':
    case 'thinking':
      return 'Thinking'
    case 'tool-input':
    case 'tool-use':
      return 'Working'
    case 'responding':
      return 'Writing'
  }
}

/** What a running tool call is doing, in a few words. */
export function toolDoing(tool: string): string {
  if (['Read', 'Grep', 'Glob', 'LSP'].includes(tool)) return 'reading'
  if (tool === 'Bash') return 'running a command'
  if (['Edit', 'Write', 'NotebookEdit'].includes(tool)) return 'editing'
  if (tool === 'Agent') return 'handing work to an agent'
  if (tool.startsWith('Web')) return 'searching the web'
  return 'working'
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'simple',
      description: 'Toggle the simple view: only your messages and Claude’s replies',
    })
    await $.state.set(isOn, (await $.store.get(STORED)) === true)

    return next(e)
  })

  on('command.run', { command: 'simple' }, async $ => {
    const { value = false } = await $.state.get(isOn)
    const turnedOn = !value
    await $.state.set(isOn, turnedOn)
    await $.store.set(STORED, turnedOn)

    return {
      text: turnedOn
        ? 'Simple view on: only your messages and Claude’s replies. /simple again to show everything.'
        : 'Simple view off: everything is shown again.',
    }
  })

  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    const { value = false } = await $.state.get(isOn)
    if (!value) return next(e)

    return next({ ...e, props: { ...e.props, message: spinnerWord(e.props.mode) } })
  })

  on('ui.render', { component: ['ToolUse', 'ToolGroup'] }, async ($, e, next) => {
    const { value = false } = await $.state.get(isOn)
    if (!value) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const doing =
      e.component === 'ToolUse'
        ? e.props.isRunning && toolDoing(e.props.tool)
        : e.props.isActive && 'working'

    return doing ? (
      <Box paddingLeft={2}>
        <Text dimColor italic>
          {doing}…
        </Text>
      </Box>
    ) : (
      <Box />
    )
  })

  on(
    'ui.render',
    { component: ['ToolResult', 'ToolProgress', 'AgentRow', 'TurnDuration', 'InfoNotice'] },
    async ($, e, next) => {
      const { value = false } = await $.state.get(isOn)
      if (!value) return next(e)
      const { Box } = $.ui.resolve(e)

      return <Box />
    },
  )
}
