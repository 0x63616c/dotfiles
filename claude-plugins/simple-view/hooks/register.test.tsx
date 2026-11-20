import type { On } from 'claude-code'
import { expect, test, type Engine } from 'claude-code/testing'

import { spinnerWord, toolDoing } from './register'

const ROW = {
  plugin: 'simple-view',
  surface: 'terminal',
  component: 'TurnDuration',
  props: {} as never,
} as const

const COMMAND = { command: 'simple', args: '', origin: { kind: 'composer' }, presentation: 'transcript' } as never

/** Stands in for the engine: a state value, a store, the statuses set, the engine's own drawing of every row. */
function engine(on: On, stored?: boolean) {
  let state: boolean | undefined
  const statuses: unknown[] = []
  const store = new Map<string, unknown>(stored === undefined ? [] : [['isOn', stored]])
  on('state.get', () => ({ value: { value: state, version: state === undefined ? 0 : 1 } }))
  on('state.set', (_, e) => {
    state = (e as { value: boolean }).value

    return { value: { isSet: true as const, version: 1 } }
  })
  on('store.get', (_, e) => ({ value: store.get((e as { key: string }).key) }))
  on('store.set', (_, e) => {
    const { key, value } = e as { key: string; value: unknown }
    store.set(key, value)

    return { value: undefined }
  })
  on('command.register', () => ({ value: { command: 'simple' } }))
  on('command.run', () => ({ text: '' }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('ui.status', (_, e) => {
    statuses.push(e)

    return { value: undefined }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })

  return { store, statuses }
}

const drawsTheEngine = async ($: Engine) => {
  const ui = await $.ui.mount(ROW)
  const engineRow = await ui.find({ type: 'Text', text: /engine/ })
  await ui.unmount()

  return engineRow !== undefined
}

test('off by default: every row is the engine own', async ($, on) => {
  engine(on)

  expect(await drawsTheEngine($)).toBe(true)
})

test('/simple hides tool rows and remembers it; again shows them', async ($, on) => {
  const { store } = engine(on)

  expect((await $.command.run(COMMAND)).text).toContain('Simple view on')
  expect(store.get('isOn')).toBe(true)
  expect(await drawsTheEngine($)).toBe(false)

  expect((await $.command.run(COMMAND)).text).toContain('Simple view off')
  expect(store.get('isOn')).toBe(false)
  expect(await drawsTheEngine($)).toBe(true)
})

test('a session starts in the view the last one left', async ($, on) => {
  engine(on, true)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  expect(await drawsTheEngine($)).toBe(false)
})

test('simple view sets no status notice: the status line marks it', async ($, on) => {
  const { statuses } = engine(on, true)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.command.run(COMMAND)
  await $.command.run(COMMAND)

  expect(statuses).toEqual([])
})

test('a running tool call leaves one dim line saying what it does', async ($, on) => {
  engine(on, true)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const call = (isRunning: boolean) =>
    $.ui.mount({
      plugin: 'simple-view',
      surface: 'terminal',
      component: 'ToolUse',
      props: { tool_use_id: 't', tool: 'Bash', input: {}, isRunning, isErrored: false, isInterrupted: false },
    })

  const running = await call(true)
  expect((await running.find({ type: 'Text', text: /running a command/ }))?.text).toBe('running a command…')
  await running.unmount()

  const done = await call(false)
  expect(await done.find({ type: 'Text' })).toBeUndefined()
  await done.unmount()
})

test('the spinner says plainly what the turn is doing', () => {
  expect(spinnerWord('thinking')).toBe('Thinking')
  expect(spinnerWord('tool-use')).toBe('Working')
  expect(spinnerWord('responding')).toBe('Writing')
  expect(toolDoing('Grep')).toBe('reading')
  expect(toolDoing('Mystery')).toBe('working')
})
