#!/usr/bin/env python
"""Plot structural comparison metrics from TMalign results.

Generates strip plots for TM-score, RMSD, and sequence identity from the
comparison results CSV (Step 7). Optionally plots pLDDT from ColabFold
results (Step 5).

Usage:
    python scripts/make_plots.py --results <results.csv> --outdir <dir>
    python scripts/make_plots.py --results <results.csv> --outdir <dir> --colabfold-csv <csv>
"""

import argparse
import os
import sys

import matplotlib as mpl
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def parse_args(args):
    parser = argparse.ArgumentParser(
        description="Plot structural comparison metrics"
    )
    parser.add_argument("--results", required=True, type=str,
                        help="Path to TMalign results CSV from Step 7")
    parser.add_argument("--outdir", required=True, type=str,
                        help="Output directory for plot images")
    parser.add_argument("--colabfold-csv", type=str, default=None,
                        help="Optional ColabFold results CSV for pLDDT plot")
    return parser.parse_args(args)


def plot_metric(df, metric, ylabel, title, prompts, replicas, outdir, filename):
    """Create a strip plot with points colored by replica, grouped by prompt."""
    palette = sns.color_palette("Set2", n_colors=len(replicas))
    plot_df = df[df["prompt"].isin(prompts) & df["replica"].isin(replicas)].copy()

    fig, ax = plt.subplots(figsize=(max(7, len(prompts) * 1.4), 3))
    sns.stripplot(
        data=plot_df, x="prompt", y=metric, hue="replica",
        hue_order=replicas, palette=palette, dodge=True,
        jitter=0.05, size=5, alpha=1.0, ax=ax,
    )
    ax.set_xlabel("")
    ax.set_ylabel(ylabel)
    ax.set_title(title, fontsize=14, fontweight="bold")
    ax.legend(title="Replica", bbox_to_anchor=(1.02, 1), loc="upper left",
              frameon=True)
    plt.tight_layout()
    plt.savefig(os.path.join(outdir, filename))
    plt.close()


def main(args):
    sns.set_theme(style="whitegrid", context="notebook", font_scale=1.1)
    mpl.rcParams.update({
        "figure.dpi": 150,
        "savefig.dpi": 300,
        "savefig.bbox": "tight",
        "axes.edgecolor": "0.3",
        "axes.linewidth": 0.8,
        "grid.alpha": 0.4,
        "font.family": "sans-serif",
    })

    outdir = args.outdir
    os.makedirs(outdir, exist_ok=True)

    # --- TMalign results ---
    df = pd.read_csv(args.results)

    df["prompt"] = df["query_id"].str.extract(r"(prompt_\d+)")
    df["replica"] = df["query_id"].str.extract(r"(replica_\d+)")
    df = df.sort_values(["prompt", "replica"])

    prompts = sorted(df["prompt"].dropna().unique())
    replicas = sorted(df["replica"].dropna().unique())

    plot_metric(
        df, "TM", "TM-score", "TM Score",
        prompts, replicas, outdir, "TM_scores.png"
    )

    plot_metric(
        df, "RMSD", "RMSD (\u00c5)", "RMSD",
        prompts, replicas, outdir, "RMSD_scores.png"
    )

    plot_metric(
        df, "seq_id", "Sequence Identity", "Sequence Identity",
        prompts, replicas, outdir, "seqID_scores.png"
    )

    print(f"Saved TM, RMSD, and sequence identity plots to {outdir}/")

    # --- ColabFold pLDDT plot (optional) ---
    if args.colabfold_csv and os.path.isfile(args.colabfold_csv):
        cf_df = pd.read_csv(args.colabfold_csv)
        cf_df["pLDDT"] = pd.to_numeric(cf_df["pLDDT"], errors="coerce")
        cf_df["prompt"] = cf_df["structure"].str.extract(r"(prompt_\d+)")
        cf_df["replica"] = cf_df["structure"].str.extract(r"(replica_\d+)")
        cf_df = cf_df.sort_values(["prompt", "replica"])

        cf_prompts = sorted(cf_df["prompt"].dropna().unique())
        cf_replicas = sorted(cf_df["replica"].dropna().unique())

        plot_metric(
            cf_df, "pLDDT", "pLDDT", "ColabFold pLDDT",
            cf_prompts, cf_replicas, outdir, "pLDDT_scores.png"
        )
        print(f"Saved pLDDT plot to {outdir}/")


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    main(args)
