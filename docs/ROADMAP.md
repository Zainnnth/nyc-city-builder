# Neon Boroughs Roadmap

## Vision

Build a stylized late-90s/early-2000s NYC city-builder prototype with district-driven generation, policy-based simulation, and iterative management gameplay.

## Phase 1 - Core Prototype (Current)

- [x] Godot project scaffold and boot scene
- [x] Placeable roads/zones/bulldoze tools
- [x] Camera pan/zoom controls
- [x] Basic simulation loop (population/jobs/money)
- [x] District-seeded generation from processed geojson
- [x] Style-profile cluster expansion
- [x] District overlay and focus camera
- [x] District policy controls (balanced/growth/profit)
- [x] Demand bars by district
- [x] Economy snapshot panel
- [x] City alerts panel
- [x] Objective milestone panel
- [x] Completion banner for all objectives
- [x] Save/load city state
- [x] Save slots + autosave + load-latest
- [x] Stroke-based undo/redo editing

## Phase 2 - Systems Depth (Next)

- [x] Road connectivity graph cost model
- [x] Traffic stress per district and commute penalties
- [x] Service layers (police/fire/sanitation/transit)
- [x] Land value + noise/crime overlays
- [x] District-specific upkeep and event hooks
- [x] Simple disasters/events (blackout, strike, heatwave)

## Phase 3 - NYC Flavor Pass

- [x] Midtown identity content pack v1 (accent/signage/archetype flavor)
- [x] District identity content packs (Midtown, LES, Harlem, FiDi, Queens West)
- [x] Style-linked building archetypes and signage density
- [x] Atmosphere pass: haze, sodium lights, retro UI accents
- [x] Audio bed by district mood/state

## Phase 4 - Productionization

- [x] Balance pass and scenario tuning (profile-based tuning controls)
- [x] Tutorial onboarding and tooltips
- [x] Build settings and export presets
- [x] Regression smoke checks and basic test harness

## Phase 5 - Authoring and Scale

- [x] Scenario authoring pack (goal cards + parameter presets)
- [x] Performance pass for larger grids and longer sessions
- [x] Release automation for tagged builds
- [x] Deterministic simulation assertions expansion

## Phase 6 - Gameplay Depth (Next)

- [ ] Goal-card win/loss validation hooks in simulation objectives
- [ ] Difficulty scaling by district era/theme progression
- [ ] Save migration/versioning hardening for future schema changes
- [ ] Optional benchmark scene for large-grid perf telemetry

## Phase 7 - Building Asset Pipeline

- [x] Asset source policy and license allowlist (no Google Earth extraction)
- [ ] NYC building dataset ingest for footprint + height + district tagging
- [x] Procedural massing generator (footprint -> lowpoly mesh kit) for fast coverage
- [x] Landmark placement rules v0 (weighted district/archetype proxies)
- [x] Hand-authored landmark pack v0 (hero proxies + LOD tiers)
- [ ] Cel-shaded material/shader pass for late-90s/early-2000s look
- [ ] District-based prefab set assignment and weighted spawn rules
- [ ] Godot import presets + optimization (LODs, occlusion, batching checks)
