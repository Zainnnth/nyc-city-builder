# Landmark Sourcing Shortlist (License-Safe)

Date: March 21, 2026

Use this shortlist to fill `data/runtime/landmark_assets.json` slots with real meshes.

## Rules

1. Only use assets with game-safe licenses (CC-BY, CC0/Public Domain, or paid commercial license).
2. Reject assets that indicate Google Earth extraction/rips.
3. Record final source + license in `data/provenance/`.
4. Convert final deliverable to `.glb` and place under `assets/landmarks/nyc/...`.

## Slot Mapping

### `empire_state_proxy` -> Empire State Building

- Primary: https://sketchfab.com/3d-models/empire-state-building-2174e71baa1d43e896461ed149dad54a
- License (at listing): CC Attribution
- Backup: https://sketchfab.com/3d-models/empire-state-building-b925e7b37b6746f5a44b0912821dc94b
- Note: avoid the BY-ND variant if edits are required.

### `chrysler_proxy` -> Chrysler Building

- Primary: https://sketchfab.com/3d-models/chrysler-building-26be9287b12d4234af009e4162135897
- License (at listing): CC Attribution
- Backup: https://sketchfab.com/3d-models/chrysler-building-6345ce92f01b4e569d6d438f5038414f
- Note: reject listings tagged/claimed as Google Earth extraction.

### `fidi_crown_proxy` -> One World Trade / FiDi crown tower stand-in

- Primary: https://sketchfab.com/3d-models/one-world-trade-center-44e60b2d0d764fdab74d33703847d38e
- License (at listing): CC Attribution
- Backup: https://sketchfab.com/3d-models/one-world-trade-center-a80c4e47df8d477c904ffff7b4ada338
- Note: verify “Standard” terms if using the backup.

### `les_neon_hub_proxy` -> LES neon hub stand-in

- Primary: https://sketchfab.com/3d-models/new-york-buildings-98faceefdc154d60a2b8617ca5e182e7
- License (at listing): CC Attribution
- Backup: https://sketchfab.com/3d-models/new-york-building-01-50d6cf330dd346f9904ab7e7549ab0a9
- Note: likely needs heavy cleanup/retopo and material simplification.

### `harlem_hall_proxy` -> Harlem cultural hall stand-in

- Primary (paid, commercial): https://sketchfab.com/3d-models/new-york-townhouse-f0e08a50353d44188b8fc1964cd2abc6
- License: Store/commercial terms
- Backup (paid, commercial): https://www.fab.com/listings/14c1dc63-b0f0-4bd9-b8b5-277fbeffcd67
- Note: prioritize paid clean topology over noisy “free rip” sources.

### `queens_exchange_proxy` -> Queens exchange hub stand-in

- Primary: https://sketchfab.com/3d-models/warehouse-building-0c37b0f92cb54e07a1e1c6c3df9f8439
- License (at listing): CC Attribution
- Backup: https://sketchfab.com/3d-models/warehouse-building-08a4f422bc634033b8023d53beaf8242
- Note: low-poly warehouse forms work as interim Queens mixed-use landmark.

## Rejected Examples

- Example rejected due extraction risk signal: https://sketchfab.com/3d-models/the-cube-luxury-apartments-queens-45bc5a351c1f4165a6238811d2c89a4d
- Reason: listing text references Google Earth-based extraction.

## Import Checklist Per Asset

1. Download source with license proof screenshot/text.
2. Clean mesh in Blender (`Ctrl+A` transforms, set pivot/base).
3. Export `.glb` to target path in `assets/landmarks/nyc/...`.
4. Run `tools/dev/validate_landmark_pack.ps1`.
5. Register source + license:
   - `python tools/pipeline/scripts/register_landmark_asset.py --landmark-key <slot> --source-id <source> --dataset-name <name> --license-id <license> --source-url <url> --scene-path <res://...glb>`
6. Launch game and tune `scene_scale`, `scene_offset_x`, `scene_offset_y` in `data/runtime/landmark_assets.json`.
