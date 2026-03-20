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
- Basic simulation tick (1 second):
  - Road-connected zones grow buildings.
  - Population/jobs capacity updates.
  - Money updates from taxes and upkeep.
- Camera pan with arrow keys.
- Mouse-wheel zoom.

## Run

1. Open Godot 4.x.
2. Import this folder: `nyc-city-builder`.
3. Press `F5` to run.

## Next Milestones

1. Add demand bars and tool hotbar UI widgets.
2. Add road connectivity/path graph with route cost.
3. Add district mood layers (Harlem, Lower East Side, Midtown).
4. Replace flat lots with sprite-kit/3D hybrid tiles.
