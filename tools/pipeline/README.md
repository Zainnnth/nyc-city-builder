# NYC Asset Pipeline (Legal-Safe)

This pipeline is for collecting and transforming NYC building data from permitted sources only.

## Goals

- Ingest open/licensed city building data.
- Normalize to a game-friendly schema.
- Assign district/neighborhood segments for future generative systems.
- Maintain provenance for every dataset.

## Folder Layout

- `config/source_policies.json`: allowed/restricted source policy rules.
- `config/district_profiles.json`: district segmentation metadata and bboxes.
- `scripts/ingest_buildings.py`: normalize source GeoJSON to internal schema.
- `scripts/segment_districts.py`: assign district tags from lon/lat bboxes.
- `../.. /data/raw/`: place downloaded source files here.
- `../.. /data/processed/`: generated outputs.
- `../.. /data/provenance/`: provenance log CSV.

## Quick Start

1. Put a source building GeoJSON in `data/raw/`.
2. Run legal/policy ingest:
   - `python tools/pipeline/scripts/ingest_buildings.py --input data/raw/buildings.geojson --source-id nyc_open_data --dataset-name mappluto_2025q4 --license-id NYC_OPEN_DATA --out data/processed/buildings_normalized.geojson`
3. Run district segmentation:
   - `python tools/pipeline/scripts/segment_districts.py --input data/processed/buildings_normalized.geojson --districts tools/pipeline/config/district_profiles.json --out data/processed/buildings_districted.geojson`

## Notes

- Current scripts use Python standard library only.
- Coordinate assumptions for district segmentation: WGS84 lon/lat (`EPSG:4326`).
- Replace bbox segmentation with full polygon tests later for better accuracy.
