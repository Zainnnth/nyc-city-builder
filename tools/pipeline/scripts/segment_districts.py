#!/usr/bin/env python3
"""
Assign district IDs and style profiles based on centroid lon/lat bboxes.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def in_bbox(lon: float, lat: float, bbox: list[float]) -> bool:
    min_lon, min_lat, max_lon, max_lat = bbox
    return min_lon <= lon <= max_lon and min_lat <= lat <= max_lat


def assign_district(feature: dict[str, Any], district_cfg: dict[str, Any]) -> None:
    props = feature.setdefault("properties", {})
    lon = float(props.get("centroid_lon", 0.0))
    lat = float(props.get("centroid_lat", 0.0))

    fallback = district_cfg.get("fallback_district_id", "unknown_district")
    assigned_id = fallback
    assigned_style = "default_mixed"

    for district in district_cfg.get("districts", []):
        bbox = district.get("bbox_lon_lat")
        if not bbox or len(bbox) != 4:
            continue
        if in_bbox(lon, lat, bbox):
            assigned_id = district.get("district_id", fallback)
            assigned_style = district.get("style_profile", assigned_style)
            break

    props["district_id"] = assigned_id
    props["style_profile"] = assigned_style


def main() -> None:
    parser = argparse.ArgumentParser(description="Segment building features into districts.")
    parser.add_argument("--input", required=True, type=Path, help="Normalized GeoJSON input.")
    parser.add_argument(
        "--districts",
        required=True,
        type=Path,
        help="District profiles JSON file.",
    )
    parser.add_argument("--out", required=True, type=Path, help="Output GeoJSON path.")
    args = parser.parse_args()

    if not args.input.exists():
        raise FileNotFoundError(f"Input not found: {args.input}")
    if not args.districts.exists():
        raise FileNotFoundError(f"District config not found: {args.districts}")

    payload = load_json(args.input)
    district_cfg = load_json(args.districts)
    features = payload.get("features", [])

    for feature in features:
        assign_district(feature, district_cfg)

    save_json(args.out, payload)
    print(f"District-tagged {len(features)} building features -> {args.out}")


if __name__ == "__main__":
    main()
