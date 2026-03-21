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
- `scripts/register_landmark_asset.py`: register landmark mesh intake, update runtime manifest, append provenance.
- `scripts/build_nyc3d_manifest.py`: scan district `.3dm` files and generate `data/raw/nyc3d/manifest.json`.
- `scripts/prepare_nyc3d_mesh_manifest.py`: map NYC community-district mesh batches to game districts + art pass metadata.
- `../../data/raw/`: place downloaded source files here.
- `../../data/processed/`: generated outputs.
- `../../data/provenance/`: provenance logs.

## Quick Start

1. Put a source building GeoJSON in `data/raw/`.
2. Run legal/policy ingest:
   - `python tools/pipeline/scripts/ingest_buildings.py --input data/raw/buildings.geojson --source-id nyc_open_data --dataset-name mappluto_2025q4 --license-id NYC_OPEN_DATA --out data/processed/buildings_normalized.geojson`
3. Run district segmentation:
   - `python tools/pipeline/scripts/segment_districts.py --input data/processed/buildings_normalized.geojson --districts tools/pipeline/config/district_profiles.json --out data/processed/buildings_districted.geojson`
4. Register landmark mesh intake:
   - `python tools/pipeline/scripts/register_landmark_asset.py --landmark-key empire_state_proxy --source-id sketchfab --dataset-name empire_state_v1 --license-id CC_BY_4_0 --source-url https://sketchfab.com/... --scene-path res://assets/landmarks/nyc/empire_state/empire_state.glb --author "Author Name" --attribution "CC BY 4.0 - Author Name"`
5. Prepare NYC 3D district mesh manifest (after `.3dm` -> `.glb` conversion):
   - `python tools/pipeline/scripts/prepare_nyc3d_mesh_manifest.py --input-manifest data/raw/nyc3d/manifest.json --dataset-name nyc3d_20260321 --license-id NYC_OPEN_DATA --allow-missing-glb`
6. Bootstrap NYC 3D input manifest from local `.3dm` files:
   - `python tools/pipeline/scripts/build_nyc3d_manifest.py`

## Schema Mapping Options

`ingest_buildings.py` supports common NYC field variants with configurable key maps:

- `--id-keys` default: `id,building_id,bin,bbl`
- `--height-keys` default: `height_m,height,bldgheight,heightroof,measured_height`
- `--floor-keys` default: `numfloors,floors,stories,stories_total`
- `--year-keys` default: `yearbuilt,year_built,yearbuilt_1,built_year`
- `--land-use-keys` default: `landuse,land_use,land_use1,primary_use,buildingclass`
- `--height-unit` choices: `meters` or `feet`

Example using feet-based source heights:

`python tools/pipeline/scripts/ingest_buildings.py --input data/raw/buildings.geojson --source-id nyc_open_data --dataset-name mappluto_2025q4 --license-id NYC_OPEN_DATA --height-unit feet --out data/processed/buildings_normalized.geojson`

## Notes

- Current scripts use Python standard library only.
- Coordinate assumptions for district segmentation: WGS84 lon/lat (`EPSG:4326`).
- Replace bbox segmentation with full polygon tests later for better accuracy.
- Landmark source policy allows licensed Sketchfab/Fab assets and blocks Google Earth extraction sources.
- NYC 3D source intake mapping config: `tools/pipeline/config/nyc3d_community_district_map.json`.
