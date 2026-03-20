# Asset Source Policy

This policy governs 3D/building source intake for Neon Boroughs.

## Scope

- Building footprints, height data, textures, 3D models, photogrammetry, and derived meshes.
- Any dataset used directly or indirectly in shipped game assets.

## Allowed Source Classes

- Public/open government data with clear reuse terms.
- Open datasets with explicit derivative-use permissions.
- Marketplace/library assets with licenses that allow redistribution in games.
- Team-authored or contractor-authored original assets transferred with usage rights.

## Restricted / Disallowed Source Classes

- Extracted Google Earth/Maps 3D meshes or tiles.
- Sources without clear license terms.
- Sources that prohibit redistribution/derivatives needed for game packaging.
- Leaked, scraped, or access-controlled content without permission.

## Minimum Intake Requirements

Every new dataset/asset batch must include:

- `source_id` and human-readable source name.
- dataset name/version/date.
- license identifier or license URL.
- attribution requirements (if any).
- whether derivatives are allowed.
- whether commercial use is allowed.
- link to raw file location and generated output location.

## Decision Rules

- `allow`: source license is explicit and compatible with distribution goals.
- `review`: license is ambiguous or has constraints that need legal check.
- `reject`: source is restricted/disallowed, or rights cannot be verified.

## Provenance Requirements

- Record every accepted ingest in `data/provenance/provenance_log.csv`.
- Keep raw files immutable in `data/raw/` (or versioned external storage).
- Keep generated files reproducible from scripts and config.

## Attribution

- Track attribution strings during ingest.
- Add required attribution text to release notes/credits before public builds.

## Policy Updates

- Update `tools/pipeline/config/source_policies.json` when source rules change.
- Document change rationale in commit message.
