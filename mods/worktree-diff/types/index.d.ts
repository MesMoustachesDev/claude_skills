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
  branch: string
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
      currentBranch: string
      selectedWorktree: string
      collapsed: string[]
      diff: SelectedDiff | null
      areTestsShown: boolean
    }
  }
}
