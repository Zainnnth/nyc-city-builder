#!/usr/bin/env python3
"""
Register a landmark mesh intake with policy validation and provenance logging.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


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


def normalize_res_path(path: str) -> str:
    return path.replace("\\", "/")


def append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fp:
        fp.write(json.dumps(payload) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Register a landmark mesh intake.")
    parser.add_argument("--landmark-key", required=True, help="Key in data/runtime/landmark_assets.json (for example empire_state_proxy).")
    parser.add_argument("--source-id", required=True, help="Source ID from source policy config.")
    parser.add_argument("--dataset-name", required=True, help="Dataset/version label for provenance.")
    parser.add_argument("--license-id", required=True, help="Declared license ID.")
    parser.add_argument("--source-url", required=True, help="Public listing URL for the asset source.")
    parser.add_argument("--scene-path", required=True, help="Target res:// scene/glb path used by landmark manifest.")
    parser.add_argument("--raw-input-path", default="", help="Optional local path of original downloaded source file.")
    parser.add_argument("--author", default="", help="Optional creator/author credit.")
    parser.add_argument("--attribution", default="", help="Optional attribution text required by source license.")
    parser.add_argument("--notes", default="", help="Optional notes (cleanup/retopo/material edits).")
    parser.add_argument("--scene-scale", type=float, default=None, help="Optional override for scene_scale.")
    parser.add_argument("--scene-offset-x", type=float, default=None, help="Optional override for scene_offset_x.")
    parser.add_argument("--scene-offset-y", type=float, default=None, help="Optional override for scene_offset_y.")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("data/runtime/landmark_assets.json"),
        help="Landmark asset manifest path.",
    )
    parser.add_argument(
        "--policy",
        type=Path,
        default=Path("tools/pipeline/config/source_policies.json"),
        help="Source policy JSON file.",
    )
    parser.add_argument(
        "--provenance-log",
        type=Path,
        default=Path("data/provenance/provenance_log.csv"),
        help="CSV file for generic provenance append.",
    )
    parser.add_argument(
        "--landmark-log",
        type=Path,
        default=Path("data/provenance/landmark_ingest_log.jsonl"),
        help="JSONL file for landmark-specific provenance records.",
    )
    args = parser.parse_args()

    if not args.manifest.exists():
        raise FileNotFoundError(f"Landmark manifest not found: {args.manifest}")
    if not args.policy.exists():
        raise FileNotFoundError(f"Policy file not found: {args.policy}")

    policy = load_json(args.policy)
    assert_source_allowed(args.source_id, args.license_id, policy)

    manifest = load_json(args.manifest)
    assets = manifest.setdefault("assets", {})
    if args.landmark_key not in assets:
        raise KeyError(f"Landmark key '{args.landmark_key}' not found in {args.manifest}")

    entry = assets[args.landmark_key]
    normalized_scene = normalize_res_path(args.scene_path)
    entry["scene_path"] = normalized_scene
    if args.scene_scale is not None:
        entry["scene_scale"] = args.scene_scale
    if args.scene_offset_x is not None:
        entry["scene_offset_x"] = args.scene_offset_x
    if args.scene_offset_y is not None:
        entry["scene_offset_y"] = args.scene_offset_y
    save_json(args.manifest, manifest)

    raw_input_path = normalize_res_path(args.raw_input_path) if args.raw_input_path else ""
    append_provenance_row(
        args.provenance_log,
        args.source_id,
        args.dataset_name,
        args.license_id,
        raw_input_path or args.source_url,
        normalized_scene,
    )

    detail_record = {
        "timestamp_utc": dt.datetime.now(dt.UTC).isoformat(),
        "landmark_key": args.landmark_key,
        "display_name": entry.get("display_name", args.landmark_key),
        "source_id": args.source_id,
        "dataset_name": args.dataset_name,
        "license_id": args.license_id,
        "source_url": args.source_url,
        "raw_input_path": raw_input_path,
        "scene_path": normalized_scene,
        "author": args.author,
        "attribution": args.attribution,
        "notes": args.notes,
    }
    append_jsonl(args.landmark_log, detail_record)

    print(f"Updated landmark manifest -> {args.manifest}")
    print(f"Registered landmark intake -> {args.landmark_key} ({normalized_scene})")
    print(f"Provenance appended -> {args.provenance_log}")
    print(f"Landmark detail log appended -> {args.landmark_log}")


if __name__ == "__main__":
    main()
