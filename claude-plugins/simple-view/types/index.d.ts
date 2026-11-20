export type SimpleViewIsOn = boolean

declare module 'claude-code' {
  interface PluginState {
    'simple-view': { isOn: SimpleViewIsOn }
  }
}
