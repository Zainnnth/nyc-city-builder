#!/usr/bin/env python3
"""
Prepare district mesh manifest + art-pass metadata from NYC 3D community district batches.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def normalize_path(path: str) -> str:
    return path.replace("\\", "/").strip()


def community_code(raw: str) -> str:
    value = raw.strip().upper()
    if not re.match(r"^[A-Z]{2}\d{2}$", value):
        raise ValueError(f"Invalid community district code '{raw}'. Expected pattern like MN01 or QN02.")
    return value


def assert_source_allowed(source_id: str, license_id: str, policy: dict[str, Any]) -> None:
    restricted = {entry["source_id"]: entry for entry in policy.get("restricted_sources", [])}
    if source_id in restricted:
        reason = restricted[source_id].get("reason", "Restricted source.")
        raise ValueError(f"Source '{source_id}' rejected by policy: {reason}")

    allowed_map = {entry["source_id"]: entry for entry in policy.get("allowed_sources", [])}
    if source_id not in allowed_map:
        raise ValueError(f"Source '{source_id}' is not listed in allowed_sources.")

    allowed_licenses = set(allowed_map[source_id].get("license_ids", []))
    if license_id not in allowed_licenses:
        raise ValueError(
            f"License '{license_id}' not valid for source '{source_id}'. "
            f"Expected one of: {sorted(allowed_licenses)}"
        )


def resolve_district_id(cd_code: str, district_map: dict[str, Any]) -> str:
    exact = district_map.get("exact_map", {})
    if cd_code in exact:
        return str(exact[cd_code])
    borough_fallback = district_map.get("borough_fallback_map", {})
    borough_code = cd_code[:2]
    if borough_code in borough_fallback:
        return str(borough_fallback[borough_code])
    return str(district_map.get("default_district_id", "outer_borough_mix"))


def style_profile_for_district(district_id: str, district_profiles: dict[str, Any]) -> str:
    for district in district_profiles.get("districts", []):
        if str(district.get("district_id", "")) == district_id:
            return str(district.get("style_profile", "default_mixed"))
    return "default_mixed"


def art_pass_for_district(district_id: str, district_identity: dict[str, Any]) -> dict[str, Any]:
    districts = district_identity.get("districts", {})
    profile: dict[str, Any]
    if district_id in districts:
        profile = dict(districts[district_id])
    else:
        profile = dict(district_identity.get("fallback", {}))
    return {
        "accent_color": profile.get("accent_color", "#C7CEDC"),
        "night_accent_color": profile.get("night_accent_color", "#3CA8A6"),
        "signage_density": float(profile.get("signage_density", 0.25)),
        "toon_variant": f"{district_id}_toon_v1",
        "material_preset": "cel_urban_90s",
    }


def append_provenance_row(
    path: Path,
    source_id: str,
    dataset_name: str,
    license_id: str,
    input_file: str,
    output_file: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_exists = path.exists()
    with path.open("a", encoding="utf-8", newline="") as fp:
        writer = csv.writer(fp)
        if not file_exists:
            writer.writerow(
                [
                    "timestamp_utc",
                    "source_id",
                    "dataset_name",
                    "license_id",
                    "input_path",
                    "output_path",
                ]
            )
        writer.writerow(
            [
                dt.datetime.now(dt.UTC).isoformat(),
                source_id,
                dataset_name,
                license_id,
                input_file,
                output_file,
            ]
        )


def append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fp:
        fp.write(json.dumps(payload) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare NYC 3D district mesh + art-pass manifest.")
    parser.add_argument("--input-manifest", required=True, type=Path, help="JSON file listing community district source and glb paths.")
    parser.add_argument("--dataset-name", required=True, help="Dataset/version label (for provenance).")
    parser.add_argument("--license-id", default="NYC_OPEN_DATA", help="Declared license ID.")
    parser.add_argument("--source-id", default="nyc_open_data", help="Source ID in source policy.")
    parser.add_argument(
        "--policy",
        type=Path,
        default=Path("tools/pipeline/config/source_policies.json"),
        help="Source policy JSON file.",
    )
    parser.add_argument(
        "--district-map",
        type=Path,
        default=Path("tools/pipeline/config/nyc3d_community_district_map.json"),
        help="Community district to game district map config.",
    )
    parser.add_argument(
        "--district-profiles",
        type=Path,
        default=Path("tools/pipeline/config/district_profiles.json"),
        help="District profiles config used to resolve style profile.",
    )
    parser.add_argument(
        "--district-identity",
        type=Path,
        default=Path("data/runtime/district_identity.json"),
        help="District identity config used to resolve art pass metadata.",
    )
    parser.add_argument(
        "--out-mesh-manifest",
        type=Path,
        default=Path("data/processed/nyc3d_district_mesh_manifest.json"),
        help="Output JSON for district mesh batches.",
    )
    parser.add_argument(
        "--out-art-pass-manifest",
        type=Path,
        default=Path("data/runtime/nyc3d_art_pass_manifest.json"),
        help="Output JSON for district art pass metadata.",
    )
    parser.add_argument(
        "--provenance-log",
        type=Path,
        default=Path("data/provenance/provenance_log.csv"),
        help="CSV file for generic provenance append.",
    )
    parser.add_argument(
        "--nyc3d-log",
        type=Path,
        default=Path("data/provenance/nyc3d_mesh_ingest_log.jsonl"),
        help="JSONL file for NYC3D mesh intake details.",
    )
    parser.add_argument(
        "--allow-missing-glb",
        action="store_true",
        help="Allow manifest generation even if glb files are not present yet.",
    )
    args = parser.parse_args()

    for required in [args.input_manifest, args.policy, args.district_map, args.district_profiles, args.district_identity]:
        if not required.exists():
            raise FileNotFoundError(f"Required input not found: {required}")

    policy = load_json(args.policy)
    assert_source_allowed(args.source_id, args.license_id, policy)
    district_map = load_json(args.district_map)
    district_profiles = load_json(args.district_profiles)
    district_identity = load_json(args.district_identity)
    batch = load_json(args.input_manifest)

    entries = batch.get("entries", [])
    if not isinstance(entries, list) or len(entries) == 0:
        raise ValueError("Input manifest requires non-empty 'entries' array.")

    source_url = str(batch.get("source_url", ""))
    output_entries: list[dict[str, Any]] = []
    art_pass_by_district: dict[str, dict[str, Any]] = {}

    for idx, raw_entry in enumerate(entries):
        if not isinstance(raw_entry, dict):
            raise ValueError(f"Entry {idx} is not an object.")

        cd = community_code(str(raw_entry.get("community_district", "")))
        source_path = normalize_path(str(raw_entry.get("source_path", "")))
        glb_path_raw = str(raw_entry.get("glb_path", ""))
        glb_path = normalize_path(glb_path_raw)
        if glb_path == "":
            raise ValueError(f"Entry {idx} ({cd}) missing glb_path.")

        glb_fs = Path(glb_path.replace("res://", ""))
        if not args.allow_missing_glb and not glb_fs.exists():
            raise FileNotFoundError(
                f"GLB path not found for {cd}: {glb_path}. Use --allow-missing-glb to stage metadata before conversion."
            )

        district_id = resolve_district_id(cd, district_map)
        style_profile = style_profile_for_district(district_id, district_profiles)
        art_pass = art_pass_for_district(district_id, district_identity)
        art_pass_by_district[district_id] = art_pass

        output_entries.append(
            {
                "community_district": cd,
                "district_id": district_id,
                "style_profile": style_profile,
                "source_path": source_path,
                "glb_path": glb_path,
                "building_count_hint": int(raw_entry.get("building_count_hint", 0)),
                "art_pass": art_pass,
            }
        )

        append_provenance_row(
            args.provenance_log,
            args.source_id,
            args.dataset_name,
            args.license_id,
            source_path or source_url or f"nyc3d:{cd}",
            glb_path,
        )
        append_jsonl(
            args.nyc3d_log,
            {
                "timestamp_utc": dt.datetime.now(dt.UTC).isoformat(),
                "source_id": args.source_id,
                "dataset_name": args.dataset_name,
                "license_id": args.license_id,
                "source_url": source_url,
                "community_district": cd,
                "district_id": district_id,
                "style_profile": style_profile,
                "source_path": source_path,
                "glb_path": glb_path,
            },
        )

    mesh_manifest = {
        "source_id": args.source_id,
        "dataset_name": args.dataset_name,
        "license_id": args.license_id,
        "source_url": source_url,
        "generated_utc": dt.datetime.now(dt.UTC).isoformat(),
        "entries": output_entries,
    }
    save_json(args.out_mesh_manifest, mesh_manifest)

    art_manifest = {
        "generated_utc": dt.datetime.now(dt.UTC).isoformat(),
        "material_preset": "cel_urban_90s",
        "district_profiles": art_pass_by_district,
    }
    save_json(args.out_art_pass_manifest, art_manifest)

    print(f"Wrote district mesh manifest -> {args.out_mesh_manifest}")
    print(f"Wrote district art-pass manifest -> {args.out_art_pass_manifest}")
    print(f"Provenance appended -> {args.provenance_log}")
    print(f"NYC3D intake detail log appended -> {args.nyc3d_log}")
    print(f"Entries processed: {len(output_entries)}")


if __name__ == "__main__":
    main()
