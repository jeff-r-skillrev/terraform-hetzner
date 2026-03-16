# Research VM — Global Instructions

These instructions apply to all work on this VM regardless of which
directory you are in or which orchestration framework is running.

## Repo Registry

A YAML file at ~/repos.yaml lists every known repository with clone URLs,
aliases, tech stack, and setup instructions. When the user mentions a repo
by name or alias, look it up there.

### Workflow when the user asks you to work on a repo

0. (pre-check) Verify sufficient disk space is available (df -h; du -sh ~/*/)
1. Parse the user's request to identify which repo they mean (match against
   `name` and `aliases` in ~/repos.yaml).
2. Check if the repo is already cloned at its `path`. If not, clone it.
3. `cd` into the repo directory.
4. If `setup` is defined and hasn't been run yet (e.g., no `node_modules/`),
   run the setup commands.
5. If the orchestration framework in use needs per-repo initialization
   (e.g., `npx claude-flow@v3alpha init`, spacebot init, etc.), check if
   that's been done and run it if not.
6. Create a feature branch off `default_branch` for the work.
7. Do the work.
8. Commit, push, and create a PR via `gh pr create`. If gh is not setup, simplly push the branch and notify the user.

## Rules

- Never commit directly to `main` (or whatever `default_branch` is).
- Always create a feature branch with a descriptive name.
- Read `notes` for each repo before taking action — some repos have
  guardrails (e.g., don't run terraform apply without approval).
- Push branches and open PRs via `gh pr create`.
- If the repo has its own CLAUDE.md, follow those instructions too —
  they take precedence over these global ones for repo-specific concerns.
