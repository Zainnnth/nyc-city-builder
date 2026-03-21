# NYC 3D Raw Intake

Place raw NYC 3D district packages here before conversion.

- Source page: https://www.nyc.gov/content/planning/pages/resources/datasets/nyc-3d-model
- Expected raw format from NYC DCP: `.3dm` by community district
- Do not commit heavy raw source files to git unless explicitly required

Recommended local structure:

- `data/raw/nyc3d/source/MN01.3dm`
- `data/raw/nyc3d/source/MN02.3dm`
- ...

After conversion to `.glb`, register files via:

- `python tools/pipeline/scripts/prepare_nyc3d_mesh_manifest.py --input-manifest data/raw/nyc3d/manifest.json --dataset-name nyc3d_YYYYMMDD --license-id NYC_OPEN_DATA`
