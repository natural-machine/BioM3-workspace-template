#!/usr/bin/env python3
"""Create a small random subset of a BioM3 training CSV for quick pipeline runs.

Usage:
    python scripts/create_mini_dataset.py data/SH3/FINAL_SH3_all_dataset_with_prompts.csv \
        -n 500 -o data/SH3_mini/FINAL_SH3_mini_all_dataset_with_prompts.csv --seed 42
"""

import argparse
import pandas as pd
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Sample rows from a BioM3 training CSV")
    parser.add_argument("input_csv", type=Path, help="Full training CSV")
    parser.add_argument("-n", "--num-samples", type=int, default=500,
                        help="Number of rows to sample (default: 500)")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="Output CSV path (default: auto-generated in same dir)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")
    args = parser.parse_args()

    df = pd.read_csv(args.input_csv)
    n = min(args.num_samples, len(df))

    mini = df.sample(n=n, random_state=args.seed)

    out_path = args.output
    if out_path is None:
        stem = args.input_csv.stem
        out_path = args.input_csv.parent / f"{stem}_mini.csv"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    mini.to_csv(out_path, index=False)

    print(f"Sampled {n} / {len(df)} rows (seed={args.seed})")
    print(f"Output: {out_path}")


if __name__ == "__main__":
    main()
