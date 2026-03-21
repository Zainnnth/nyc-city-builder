# Provenance Log

`provenance_log.csv` is append-only and records:

- UTC timestamp
- Source ID
- Dataset name/version
- License ID
- Input file path
- Output file path

Do not manually edit historical rows except to correct obvious metadata mistakes.

`landmark_ingest_log.jsonl` is append-only and records landmark-specific intake details:

- landmark key/display name
- source listing URL
- author/attribution
- license ID and source ID
- target `scene_path` used by runtime
