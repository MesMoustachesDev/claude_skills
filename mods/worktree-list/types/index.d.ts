export type Worktree = {
  path: string
  branch: string
  sha: string
  isLocked: boolean
  isPrunable: boolean
  isCurrent: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'worktree-list': {
      worktrees: Shaped<Worktree[]>
      root: string
    }
  }
}
