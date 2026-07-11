# Tai Assistant Dev Workflow

> Operational guide — not part of the constitutional layer. Start with [`Docs/README.md`](README.md).

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

## TestFlight proxy auth (required before Archive)

1. Copy `TaiAssistant/Config/Secrets.xcconfig.example` to `TaiAssistant/Config/Secrets.xcconfig`.
2. Set `AI_PROXY_BEARER_TOKEN` to the current `TAI_PROXY_TOKEN` value in Cloudflare Workers.
3. Archive with the **Release** configuration (token is injected into the app Info.plist at build time).
4. If a token was ever committed to git, rotate `TAI_PROXY_TOKEN` in Cloudflare before distributing builds.

`Secrets.xcconfig` is gitignored. Do not commit bearer tokens.

## Commit rules

Before every commit, run:

```bash

git branch --show-current

git status --short

git diff --cached --name-only
```

