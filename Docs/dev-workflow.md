# Tai Assistant Dev Workflow

## Current integration branch

- Main active integration branch: `feature/checkin-figma-ui-convergence`

## Branch naming rules

- Feature work: `feature/<area>`

- Small focused fixes: `fix/<area>`

- Experiments or spikes: `spike/<area>`

Examples:

- `feature/checkin-figma-ui-convergence`

- `feature/openai-integration-clean`

- `fix/checkin-camera-close-button`

## Multi-agent branch rules

- Every agent must be given an explicit branch name.

- Every agent must be given explicit file ownership.

- Do not let two agents edit the same shared root files unless planned.

## Shared-file hotspots

These files are high-risk for merge conflicts and should be changed carefully:

- `TaiAssistant/App/Navigation/AppShellView.swift`

- `TaiAssistant/App/Dependencies/AppDependencies.swift`

- `TaiAssistant/App/AppConfig.swift`

- `TaiAssistant/App/TaiAssistantApp.swift`

## Commit rules

Before every commit, run:

```bash

git branch --show-current

git status --short

git diff --cached --name-only