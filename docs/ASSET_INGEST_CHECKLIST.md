# Asset Ingest Checklist

Use this checklist before importing new building/model datasets.

## 1) Source Intake Gate

- [ ] Source appears in `tools/pipeline/config/source_policies.json` as allowed.
- [ ] Source is not in restricted list (for example, extracted Google Earth meshes).
- [ ] License ID and/or license URL captured.
- [ ] Commercial + derivative rights verified for project goals.
- [ ] Attribution obligations identified.

## 2) Dataset Registration

- [ ] Dataset named with stable version/date.
- [ ] Raw files stored in `data/raw/` with consistent naming.
- [ ] Ingest command prepared with `--source-id`, `--dataset-name`, `--license-id`.
- [ ] Provenance entry appended to `data/provenance/provenance_log.csv`.

## 3) Geometry/Data Quality Gate

- [ ] Coordinate system verified (prefer `EPSG:4326` before segmentation).
- [ ] Required fields available (footprint or centroid, optional height).
- [ ] Invalid/empty geometries filtered.
- [ ] Bounding sanity check against NYC extents.

## 4) District Segmentation Gate

- [ ] District tagging run with `segment_districts.py`.
- [ ] Output includes `district_id` and `style_profile`.
- [ ] Spot-check sample records by district.
- [ ] Fallback district behavior verified.
- [ ] For NYC3D mesh batches, run:
  - [ ] `python tools/pipeline/scripts/prepare_nyc3d_mesh_manifest.py --input-manifest ... --dataset-name ...`
  - [ ] Verify generated `data/processed/nyc3d_district_mesh_manifest.json`.

## 5) Game Integration Gate

- [ ] Processed output placed in `data/processed/`.
- [ ] For NYC3D building catalogs:
  - [ ] `data/processed/nyc3d_buildings/<DISTRICT>/catalog.json` generated.
  - [ ] Optional `data/runtime/nyc3d_building_catalog_index.json` updated (if using explicit index).
- [ ] Scene boot validates with new data.
- [ ] Smoke checks pass:
  - [ ] `powershell -ExecutionPolicy Bypass -File tools/smoke/run_smoke.ps1`
- [ ] Visual sanity check in-game (no catastrophic overdraw or missing districts).

## 6) 3D Asset-Specific Gate (When Adding Meshes)

- [ ] Mesh source license allows game redistribution.
- [ ] LOD strategy defined (L0/L1/L2 or equivalent).
- [ ] Materials follow project style direction (cel-shaded target).
- [ ] Import settings reviewed for memory/perf.
- [ ] Attribution and author credit text prepared.
- [ ] Landmark intake registered with:
  - [ ] `python tools/pipeline/scripts/register_landmark_asset.py ...`
  - [ ] `data/provenance/landmark_ingest_log.jsonl` appended.

## Done Criteria

- All required boxes checked for the dataset class.
- Ingest steps reproducible from committed scripts/config.
- Commit includes data path, provenance update, and validation note.
