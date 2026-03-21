#!/usr/bin/env python3
"""
Build NYC3D manifest entries from community district .3dm files.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def save_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def all_community_districts() -> list[str]:
    out: list[str] = []
    out.extend([f"MN{i:02d}" for i in range(1, 13)])
    out.extend([f"BX{i:02d}" for i in range(1, 13)])
    out.extend([f"BK{i:02d}" for i in range(1, 19)])
    out.extend([f"QN{i:02d}" for i in range(1, 15)])
    out.extend([f"SI{i:02d}" for i in range(1, 4)])
    return out


def resolve_existing_codes(source_dir: Path) -> set[str]:
    codes: set[str] = set()
    if not source_dir.exists():
        return codes
    for path in source_dir.glob("*.3dm"):
        code = path.stem.strip().upper()
        if len(code) == 4:
            codes.add(code)
    return codes


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate NYC3D manifest.json from district .3dm files.")
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("data/raw/nyc3d/source"),
        help="Directory containing NYC district .3dm files (for example MN01.3dm).",
    )
    parser.add_argument(
        "--out-manifest",
        type=Path,
        default=Path("data/raw/nyc3d/manifest.json"),
        help="Output manifest file path.",
    )
    parser.add_argument(
        "--include-missing",
        action="store_true",
        help="Include all 59 district codes even if .3dm files are not present yet.",
    )
    parser.add_argument(
        "--source-url",
        default="https://www.nyc.gov/content/planning/pages/resources/datasets/nyc-3d-model",
        help="Source URL stamped into manifest metadata.",
    )
    args = parser.parse_args()

    known_codes = all_community_districts()
    existing_codes = resolve_existing_codes(args.source_dir)
    selected_codes = known_codes if args.include_missing else [c for c in known_codes if c in existing_codes]
    if not selected_codes:
        raise ValueError(
            "No district .3dm files found. Put files in data/raw/nyc3d/source or use --include-missing."
        )

    entries: list[dict[str, Any]] = []
    for code in selected_codes:
        entries.append(
            {
                "community_district": code,
                "source_path": f"data/raw/nyc3d/source/{code}.3dm",
                "glb_path": f"assets/buildings/nyc3d/{code}.glb",
                "building_count_hint": 0,
            }
        )

    payload = {
        "source_url": args.source_url,
        "entries": entries,
    }
    save_json(args.out_manifest, payload)
    print(f"Wrote manifest -> {args.out_manifest}")
    print(f"Entries: {len(entries)}")


if __name__ == "__main__":
    main()
