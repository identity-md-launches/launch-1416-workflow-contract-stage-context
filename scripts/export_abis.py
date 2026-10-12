#!/usr/bin/env python3
"""Export ABI arrays from Foundry artifacts, or verify the checked-in exports."""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if an ABI export differs")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    for name in ("LaunchToken", "PulseDrone"):
        artifact_path = root / "out" / f"{name}.sol" / f"{name}.json"
        if not artifact_path.is_file():
            raise SystemExit(f"Missing {artifact_path.relative_to(root)}; run forge build first.")
        artifact = json.loads(artifact_path.read_text())
        abi = artifact["abi"]
        destination = root / "docs" / "abi" / f"{name}.json"
        if args.check:
            if not destination.is_file() or json.loads(destination.read_text()) != abi:
                raise SystemExit(f"Stale ABI: {destination.relative_to(root)}")
            print(f"Verified {destination.relative_to(root)}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(json.dumps(abi, indent=2) + "\n")
            print(f"Exported {destination.relative_to(root)}")


if __name__ == "__main__":
    main()
