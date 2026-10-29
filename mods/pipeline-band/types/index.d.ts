export type PipelineSnapshot = {
  feature: string
  step: string
  waiting: string
}

declare module 'claude-code' {
  interface PluginState {
    'pipeline-band': { snapshot: PipelineSnapshot | null; isHidden: boolean }
  }
}
