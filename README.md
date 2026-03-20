# Neon Boroughs

A Godot 4 starter project for a city-builder inspired by late-90s / early-2000s New York.

## Creative Direction

- Dense Manhattan block logic, scaffolding, water towers, signage, elevated transit.
- Color direction based on the Skyscraper Museum "Building the Skyline" image reference:
  archival urban tones with neon accents.
- Style target: vaporwave-adjacent, but grittier and less pastel.

## Roadmap

- Project roadmap and build checklist:
  - `docs/ROADMAP.md`
- Development workflow:
  - `docs/DEVELOPMENT_PLAYBOOK.md`

## Current Prototype

- Paintable grid with tools:
  - `1` Road
  - `2` Residential
  - `3` Commercial
  - `4` Industrial
  - `5` Bulldoze
- Click-and-drag placement on the map.
- Edit history:
  - `Ctrl+Z` undo
  - `Ctrl+Y` redo
- District-seeded procedural blocks from GeoJSON data:
  - Loads `data/processed/buildings_districted.geojson` if available.
  - Falls back to `data/raw/sample_buildings.geojson` otherwise.
  - Seeds zones/building levels by district style profile.
  - Expands clusters using `data/runtime/style_profiles.json`.
  - Deterministic generation via `DistrictGenerator.world_seed`.
  - Procedural massing layer (2.5D):
    - Runtime-generated block forms from seeded records (no external meshes required)
    - Style-driven shaping from `data/runtime/massing_profiles.json`
    - District-tinted cel-style shading pass for quick skyline readability
    - Landmark pack v0 overlays weighted hero proxies by district/archetype
    - Landmark config in `data/runtime/landmark_pack.json`
    - Hand-authored landmark asset manifest + LOD rules in `data/runtime/landmark_assets.json`
- In-game seed panel:
  - Enter a seed and click `Apply Seed` to regenerate neighborhoods.
  - Click `Randomize` for a new deterministic layout.
  - `Save City` / `Load City` persist full simulation state (`user://savegame.json`).
  - Save slots: `Slot 1-3` (`user://savegame_1.json` etc).
  - `Autosave` performs rolling slot saves every ~20 seconds.
  - `Load Latest` loads the newest slot by file timestamp.
  - Time controls: `Pause/Resume`, `1x`, `3x` simulation speed.
  - Scenario presets:
    - `Balanced Preset`
    - `Midtown Boom`
    - `Borough Buildout`
  - Scenario authoring pack:
    - New `Scenario Cards` panel with authored setup cards
    - Card data loaded from `data/runtime/scenario_cards.json`
    - Cards can apply seed, district policies, balance profile, and service sliders
    - Includes per-card goal text for run planning
  - Balance profile tuning:
    - `Standard`, `Civic Push`, `Austerity Crunch`
    - Adjusts growth/tax/upkeep/event pressure and cash objective target
  - Tutorial onboarding + tooltips:
    - First-run guided steps with `Next/Skip`
    - Persistent completion state (`user://tutorial_state.json`)
    - Context tooltips on key controls
  - Service layer controls:
    - `Police`, `Fire`, `Sanitation`, `Transit` sliders
    - Directly influence growth, upkeep, demand stress, and alerts
  - Overlay controls:
    - `None`, `Land Value`, `Noise`, `Crime`
    - Includes live average overlay metrics
  - District identity pass (v1):
    - `midtown_core` now uses higher signage density and accent tinting
    - Identity packs loaded for Midtown, LES, Harlem, FiDi, and Queens West
    - District archetypes are seeded per tile and surfaced in demand rows/popup
    - Identity profile values tune commercial growth/tax/noise behavior
    - Archetype-linked signage rendering changes stripe density/color patterns
  - District event controls:
    - Auto-spawned events by district (`Blackout`, `Transit Strike`, `Heatwave`)
    - Manual `Trigger Event` button for balancing tests
    - Active/cooldown status + latest event history
  - Atmosphere pass (v1):
    - Animated haze and sodium-light pools across the map
    - Retro scanline treatment and pulsing HUD accent colors
    - CRT-inspired panel/button skin for the management UI
  - Dynamic audio bed (v1):
    - Procedural ambient drone + pulse generated at runtime (no external assets)
    - Reacts to dominant district demand profile and city stress pressure
    - Responds to active events (`Blackout`, `Transit Strike`, `Heatwave`)
  - Economy snapshot panel with per-tick deltas and pressure indicators.
  - City alerts panel for budget, pressure, and connectivity warnings.
  - Objectives panel for milestone progression.
  - Milestone banner appears when all objectives are complete.
- Live district demand bars:
  - Shows per-district demand index and `R/C/I` demand values.
  - Shows traffic stress, service stress, and district upkeep hook.
  - Shows currently active district event (if any).
  - Shows district identity/archetype hint.
  - Updates continuously from simulation telemetry.
  - `Focus District` jumps camera to that neighborhood cluster.
  - Opens district detail popup with demand breakdown.
  - District policy buttons in popup:
    - `Balanced` default
    - `Growth` (faster build-up, weaker tax efficiency)
    - `Profit` (stronger tax efficiency, slower growth)
- Basic simulation tick (1 second):
  - Road-connected zones grow buildings.
  - Population/jobs capacity updates with service and event modifiers.
  - Money updates from taxes and upkeep with district/style/event modifiers.
  - District-specific upkeep hooks recalculate from live stress signals.
- Camera pan with arrow keys.
- Mouse-wheel zoom.
- `G` toggles district overlay visualization.

## Run

1. Open Godot 4.x.
2. Import this folder: `nyc-city-builder`.
3. Press `F5` to run.

## Export

- Presets file: `export_presets.cfg`
- Targets configured:
  - `Windows Desktop` -> `build/windows/NeonBoroughs.exe`
  - `Linux/BSD` -> `build/linux/NeonBoroughs.x86_64`
  - `Web` -> `build/web/index.html`
- CLI examples:
  - `godot --headless --path . --export-release "Windows Desktop" build/windows/NeonBoroughs.exe`
  - `godot --headless --path . --export-release "Linux/BSD" build/linux/NeonBoroughs.x86_64`
  - `godot --headless --path . --export-release "Web" build/web/index.html`
- Note: release templates must be installed in Godot for exports to succeed.

## Smoke Checks

- Harness script: `scripts/smoke_harness.gd`
- Runner: `tools/smoke/run_smoke.ps1`
- Full local dev gate:
  - `powershell -ExecutionPolicy Bypass -File tools/dev/run_all_checks.ps1`
- Run:
  - `powershell -ExecutionPolicy Bypass -File tools/smoke/run_smoke.ps1`
- The harness validates:
  - Main scene boot and required nodes (`CityGrid`, `DistrictGenerator`, `SeedPanel`, `AudioBed`)
  - Core simulation API snapshots and shape checks
  - State export/import roundtrip
  - District regeneration call path
- CI:
  - GitHub Actions workflow at `.github/workflows/smoke.yml`
  - Runs smoke checks automatically on pushes to `main` and pull requests
  - Includes deterministic seeded simulation signature assertions

## Release Automation

- Workflow: `.github/workflows/release.yml`
- Trigger:
  - Push tag matching `v*` (example: `v0.1.0`)
  - Manual `workflow_dispatch`
- Output artifacts:
  - `neon-boroughs-windows.zip`
  - `neon-boroughs-linux.tar.gz`
  - `neon-boroughs-web.zip`
  - `SHA256SUMS.txt`
- Artifacts are attached to the GitHub Release for matching tags.

## Legal-Safe Data Pipeline

- Pipeline docs: `tools/pipeline/README.md`
- Policy config: `tools/pipeline/config/source_policies.json`
- District config: `tools/pipeline/config/district_profiles.json`
- Asset source policy: `docs/ASSET_POLICY.md`
- Asset ingest checklist: `docs/ASSET_INGEST_CHECKLIST.md`
- Massing profile config: `data/runtime/massing_profiles.json`
- Landmark pack config: `data/runtime/landmark_pack.json`
- Landmark asset manifest: `data/runtime/landmark_assets.json`
- Sample input: `data/raw/sample_buildings.geojson`

Example run:

```bash
python tools/pipeline/scripts/ingest_buildings.py \
  --input data/raw/sample_buildings.geojson \
  --source-id nyc_open_data \
  --dataset-name sample_demo \
  --license-id NYC_OPEN_DATA \
  --out data/processed/buildings_normalized.geojson

python tools/pipeline/scripts/segment_districts.py \
  --input data/processed/buildings_normalized.geojson \
  --districts tools/pipeline/config/district_profiles.json \
  --out data/processed/buildings_districted.geojson
```

## Next Milestones

1. Goal-card win/loss validation hooks in simulation objectives.
2. Difficulty scaling by district era/theme progression.
3. Save migration/versioning hardening for future schema changes.
4. Optional benchmark scene for large-grid perf telemetry.
5. Building asset pipeline (licensed sources, procedural massing, landmark pack, cel-shaded integration).
