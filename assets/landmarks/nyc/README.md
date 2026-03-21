# NYC Landmark Mesh Pack

Drop licensed `.glb` landmark meshes into the subfolders below using these filenames:

- `assets/landmarks/nyc/empire_state/empire_state.glb`
- `assets/landmarks/nyc/chrysler/chrysler.glb`
- `assets/landmarks/nyc/fidi_crown/fidi_crown.glb`
- `assets/landmarks/nyc/les_neon_hub/les_neon_hub.glb`
- `assets/landmarks/nyc/harlem_hall/harlem_hall.glb`
- `assets/landmarks/nyc/queens_exchange/queens_exchange.glb`

Runtime behavior:

- If a `.glb` exists and imports as a scene, `MassingLayer` will instantiate it.
- If missing or invalid, it falls back to `res://scenes/landmarks/generic_landmark.tscn`.

Keep source/license metadata in `data/provenance/` and ensure compliance with `docs/ASSET_POLICY.md`.
