# Neon Boroughs

A Godot 4 starter project for a city-builder inspired by late-90s / early-2000s New York.

## Creative Direction

- Dense Manhattan block logic, scaffolding, water towers, signage, elevated transit.
- Color direction based on the Skyscraper Museum "Building the Skyline" image reference:
  archival urban tones with neon accents.
- Style target: vaporwave-adjacent, but grittier and less pastel.

## Current Prototype

- Paintable grid with tools:
  - `1` Road
  - `2` Residential
  - `3` Commercial
  - `4` Industrial
  - `5` Bulldoze
- Click-and-drag placement on the map.
- District-seeded procedural blocks from GeoJSON data:
  - Loads `data/processed/buildings_districted.geojson` if available.
  - Falls back to `data/raw/sample_buildings.geojson` otherwise.
  - Seeds zones/building levels by district style profile.
  - Expands clusters using `data/runtime/style_profiles.json`.
  - Deterministic generation via `DistrictGenerator.world_seed`.
- In-game seed panel:
  - Enter a seed and click `Apply Seed` to regenerate neighborhoods.
  - Click `Randomize` for a new deterministic layout.
- Basic simulation tick (1 second):
  - Road-connected zones grow buildings.
  - Population/jobs capacity updates.
  - Money updates from taxes and upkeep with district/style modifiers.
- Camera pan with arrow keys.
- Mouse-wheel zoom.
- `G` toggles district overlay visualization.

## Run

1. Open Godot 4.x.
2. Import this folder: `nyc-city-builder`.
3. Press `F5` to run.

## Legal-Safe Data Pipeline

- Pipeline docs: `tools/pipeline/README.md`
- Policy config: `tools/pipeline/config/source_policies.json`
- District config: `tools/pipeline/config/district_profiles.json`
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

1. Add demand bars and tool hotbar UI widgets.
2. Add road connectivity/path graph with route cost.
3. Add district mood layers (Harlem, Lower East Side, Midtown).
4. Replace flat lots with sprite-kit/3D hybrid tiles.
