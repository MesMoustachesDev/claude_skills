export type ChangedFile = {
  path: string
  status: string
  added: number
  deleted: number
}

export type PipelineWorktree = {
  name: string
  dir: string
  base: string
  mergeBase: string
  files: ChangedFile[]
  error: string
}

export type SelectedDiff = {
  worktree: string
  path: string
  source: string
}

declare module 'claude-code' {
  interface PluginState {
    'worktree-diff': {
      worktrees: PipelineWorktree[]
      selectedWorktree: string
      collapsed: string[]
      diff: SelectedDiff | null
      areTestsShown: boolean
    }
  }
}
