#!/usr/bin/env python3
"""
Normalize source building GeoJSON and enforce source policy checks.
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


def polygon_centroid(coords: list[list[float]]) -> tuple[float, float]:
    if not coords:
        return (0.0, 0.0)
    ring = coords[0] if isinstance(coords[0][0], list) else coords
    if not ring:
        return (0.0, 0.0)

    lon_sum = 0.0
    lat_sum = 0.0
    count = 0
    for point in ring:
        if len(point) < 2:
            continue
        lon_sum += float(point[0])
        lat_sum += float(point[1])
        count += 1
    if count == 0:
        return (0.0, 0.0)
    return (lon_sum / count, lat_sum / count)


def extract_height_meters(props: dict[str, Any]) -> float:
    candidates = ["height_m", "height", "bldgheight", "numfloors"]
    for key in candidates:
        if key not in props:
            continue
        raw = props[key]
        try:
            value = float(raw)
        except (TypeError, ValueError):
            continue
        if key == "numfloors":
            return max(0.0, value * 3.2)
        return max(0.0, value)
    return 12.0


def normalize_feature(feature: dict[str, Any], idx: int) -> dict[str, Any]:
    geom = feature.get("geometry") or {}
    props = feature.get("properties") or {}
    geom_type = geom.get("type")
    coords = geom.get("coordinates", [])

    centroid_lon = 0.0
    centroid_lat = 0.0
    if geom_type == "Polygon":
        centroid_lon, centroid_lat = polygon_centroid(coords)
    elif geom_type == "MultiPolygon" and coords:
        centroid_lon, centroid_lat = polygon_centroid(coords[0])

    source_id = str(props.get("id") or props.get("building_id") or f"feature_{idx}")
    height_m = extract_height_meters(props)
    approx_floors = max(1, int(round(height_m / 3.2)))

    return {
        "type": "Feature",
        "geometry": geom,
        "properties": {
            "building_id": source_id,
            "height_m": round(height_m, 2),
            "approx_floors": approx_floors,
            "year_built": props.get("yearbuilt") or props.get("year_built"),
            "land_use": props.get("landuse") or props.get("land_use"),
            "centroid_lon": round(centroid_lon, 7),
            "centroid_lat": round(centroid_lat, 7),
            "district_id": None,
            "style_profile": None,
            "toon_variant": None
        }
    }


def append_provenance_row(
    path: Path,
    source_id: str,
    dataset_name: str,
    license_id: str,
    input_file: Path,
    output_file: Path,
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
                str(input_file),
                str(output_file),
            ]
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest and normalize building GeoJSON.")
    parser.add_argument("--input", required=True, type=Path, help="Path to source GeoJSON.")
    parser.add_argument("--source-id", required=True, help="Source ID from policy config.")
    parser.add_argument("--dataset-name", required=True, help="Dataset/version label.")
    parser.add_argument("--license-id", required=True, help="Declared license ID.")
    parser.add_argument("--out", required=True, type=Path, help="Output normalized GeoJSON.")
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
        help="CSV file for provenance append.",
    )
    args = parser.parse_args()

    if not args.input.exists():
        raise FileNotFoundError(f"Input not found: {args.input}")
    if not args.policy.exists():
        raise FileNotFoundError(f"Policy file not found: {args.policy}")

    policy = load_json(args.policy)
    assert_source_allowed(args.source_id, args.license_id, policy)

    geojson = load_json(args.input)
    features = geojson.get("features", [])
    normalized = [normalize_feature(feature, idx) for idx, feature in enumerate(features)]
    payload = {"type": "FeatureCollection", "features": normalized}
    save_json(args.out, payload)

    append_provenance_row(
        args.provenance_log,
        args.source_id,
        args.dataset_name,
        args.license_id,
        args.input,
        args.out,
    )

    print(f"Normalized {len(normalized)} building features -> {args.out}")
    print(f"Provenance appended -> {args.provenance_log}")


if __name__ == "__main__":
    main()
