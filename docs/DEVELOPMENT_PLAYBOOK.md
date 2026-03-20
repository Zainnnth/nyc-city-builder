# Development Playbook

This file defines the default way to keep development moving with low regression risk.

## Loop

1. Pick one vertical slice from `docs/ROADMAP.md`.
2. Define a pass/fail check before coding.
3. Implement the smallest usable version.
4. Run smoke checks:
   - `powershell -ExecutionPolicy Bypass -File tools/smoke/run_smoke.ps1`
5. Update docs (`README.md`, roadmap line item).
6. Commit and push.

## Change Scope Rules

- Keep each commit focused on one feature or one fix.
- Prefer data-driven configs over hardcoded constants.
- Preserve save/load compatibility when adding new state.
- Add UI control + telemetry together for new systems.

## Quality Gate

A change is ready only if:

- Headless load passes.
- Smoke harness passes.
- Existing saves still import.
- New behavior is visible in UI or logs.

## Priority Order

1. Stability and regression prevention.
2. Systems depth and balance.
3. UX clarity.
4. Visual polish.

## Suggested Next Backlog

- Asset source policy + ingest checklist adoption in daily workflow.
- Goal-card completion conditions integrated into objective system.
- Difficulty scaling pass (era-themed progression pressure).
- Save migration/versioning compatibility tests.
- Optional benchmark harness for large-grid frame/tick budgets.
- Building asset pipeline: licensed source ingest + procedural massing + landmark integration.
