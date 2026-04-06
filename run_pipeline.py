#!/usr/bin/env python3
"""Config-driven pipeline runner for BioM3.

Reads a TOML config file and executes the specified pipeline steps in
sequence, activating the correct conda/venv environment for each step.

Usage:
    python run_pipeline.py <config.toml>
    python run_pipeline.py <config.toml> --steps 4 5 5b 6 7
    python run_pipeline.py <config.toml> --dry-run
"""

import argparse
import shlex
import subprocess
import sys
import tomllib
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def get_version() -> str:
    return (SCRIPT_DIR / "VERSION").read_text().strip()


# Step ID → (script path, environment key from [environments])
# Environment key of None means no activation needed.
STEPS = {
    "1":  ("pipeline/01_embedding.sh",            "biom3"),
    "2":  ("pipeline/02_finetune.sh",              "biom3"),
    "3":  ("pipeline/03_generate.sh",              "biom3"),
    "4":  ("pipeline/04_colabfold.sh",             "colabfold"),
    "5":  ("pipeline/05_blast_search.sh",          "blast"),
    "5b": ("pipeline/05b_fetch_hit_structures.sh", None),
    "6":  ("pipeline/06_compare_structures.sh",    "biom3"),
    "7":  ("pipeline/07_plot_results.sh",           "biom3"),
    "8":  ("pipeline/08_webapp.sh",                "biom3"),
}

# Step 8 (webapp) is interactive/blocking — excluded from default order.
# Use --steps 8 to launch it explicitly.
STEP_ORDER = ["1", "2", "3", "4", "5", "5b", "6", "7"]

STEP_NAMES = {
    "1":  "Embedding",
    "2":  "Finetuning",
    "3":  "Generation",
    "4":  "ColabFold Structure Prediction",
    "5":  "BLAST Search",
    "5b": "Fetch Reference Structures",
    "6":  "Structure Comparison (TMalign)",
    "7":  "Plot Results",
    "8":  "Web App",
}


def normalize_step_id(s) -> str:
    """Normalize a step ID to its canonical string form."""
    s = str(s).lower().strip()
    if s in STEPS:
        return s
    sys.exit(f"Error: invalid step ID '{s}'. Valid: {list(STEPS.keys())}")


def load_config(path: Path) -> dict:
    with open(path, "rb") as f:
        return tomllib.load(f)


def derive_paths(cfg: dict) -> dict:
    """Compute all intermediate paths from config, following project conventions.

    Any path can be overridden explicitly in [paths]. Otherwise, paths are
    derived from output_dir and input file prefixes.
    """
    paths = cfg.get("paths", {})
    outdir = paths["output_dir"]

    # Derive prefix from input_csv (Steps 1-2) or prompts_csv (Steps 3+)
    input_csv = paths.get("input_csv", "")
    prompts_csv = paths.get("prompts_csv", "")
    input_prefix = Path(input_csv).stem if input_csv else ""
    prompts_prefix = Path(prompts_csv).stem if prompts_csv else ""

    d = {
        "output_dir":       outdir,
        "embeddings_dir":   f"{outdir}/embeddings",
        "finetuning_dir":   f"{outdir}/finetuning",
        "generation_dir":   f"{outdir}/generation",
        "samples_dir":      f"{outdir}/samples",
        "structures_dir":   f"{outdir}/structures",
        "blast_dir":        f"{outdir}/blast",
        "comparison_dir":   f"{outdir}/comparison",
        "images_dir":       f"{outdir}/images",
        "input_csv":        input_csv,
        "prompts_csv":      prompts_csv,
        "input_prefix":     input_prefix,
        "prompts_prefix":   prompts_prefix,
    }

    # HDF5 from Step 1
    d["hdf5_file"] = paths.get(
        "hdf5_file",
        f"{d['embeddings_dir']}/{input_prefix}.compiled_emb.hdf5"
    )

    # Model weights from Step 2 (auto-detect if not set)
    d["model_weights"] = paths.get("model_weights", "")

    # .pt file from Step 3
    d["pt_file"] = paths.get(
        "pt_file",
        f"{d['generation_dir']}/{prompts_prefix}.ProteoScribe_output.pt"
    )

    # Epochs (optional override for Step 2)
    d["epochs"] = paths.get("epochs", "")

    # FASTA from Step 3 (--fasta_merge output)
    d["fasta_file"] = f"{d['samples_dir']}/all_sequences.fasta"

    # Reference structures from Step 5/5b
    d["reference_dir"] = f"{d['blast_dir']}/reference_structures"

    # ColabFold results from Step 4
    d["colabfold_csv"] = f"{d['structures_dir']}/colabfold_results.csv"

    # BLAST results from Step 5
    d["blast_tsv"] = f"{d['blast_dir']}/blast_hit_results.tsv"

    # TMalign results from Step 6
    d["results_csv"] = f"{d['comparison_dir']}/results.csv"

    return d


def auto_detect_weights(finetuning_dir: str) -> str:
    """Find the most recent state_dict.best.pth under a finetuning checkpoint dir."""
    ckpt_dir = Path(finetuning_dir) / "checkpoints"
    if not ckpt_dir.exists():
        return ""
    candidates = sorted(
        ckpt_dir.rglob("state_dict.best.pth"),
        key=lambda p: p.stat().st_mtime,
    )
    return str(candidates[-1]) if candidates else ""


def build_step_args(step: str, cfg: dict, d: dict) -> list[str]:
    """Build the CLI argument list for a given step script."""
    blast_cfg = cfg.get("blast", {})
    gen_cfg = cfg.get("generation", {})

    match step:
        case "1":
            return [d["input_csv"], d["embeddings_dir"]]

        case "2":
            ft_cfg = cfg.get("finetuning", {})
            args = [d["hdf5_file"], d["finetuning_dir"]]
            if d["epochs"]:
                args.append(str(d["epochs"]))
            if ft_cfg.get("config"):
                args += ["--config", ft_cfg["config"]]
            return args

        case "3":
            weights = d["model_weights"]
            if not weights:
                weights = auto_detect_weights(d["finetuning_dir"])
            if not weights:
                sys.exit(
                    "Error: No model_weights specified and none found in "
                    f"{d['finetuning_dir']}/checkpoints/. "
                    "Set paths.model_weights in the config."
                )
            args = [weights, d["prompts_csv"], d["generation_dir"]]
            # Always produce FASTA output for downstream steps
            args += ["--fasta", "--fasta_merge",
                     "--fasta_dir", d["samples_dir"]]
            if gen_cfg.get("unmasking_order"):
                args += ["--unmasking_order", gen_cfg["unmasking_order"]]
            if gen_cfg.get("token_strategy"):
                args += ["--token_strategy", gen_cfg["token_strategy"]]
            if gen_cfg.get("animate_prompts"):
                args += ["--animate_prompts"] + [
                    str(x) for x in gen_cfg["animate_prompts"]
                ]
            if gen_cfg.get("animate_replicas"):
                args += ["--animate_replicas", str(gen_cfg["animate_replicas"])]
            if gen_cfg.get("animation_dir"):
                args += ["--animation_dir", gen_cfg["animation_dir"]]
            if gen_cfg.get("animation_style"):
                args += ["--animation_style", gen_cfg["animation_style"]]
            if gen_cfg.get("animation_metrics"):
                args += ["--animation_metrics"] + [
                    str(x) for x in gen_cfg["animation_metrics"]
                ]
            if gen_cfg.get("store_probabilities"):
                args += ["--store_probabilities"]
            return args

        case "4":
            return [d["samples_dir"], d["structures_dir"]]

        case "5":
            db = blast_cfg.get("db", "swissprot")
            threads = blast_cfg.get("threads", 16)
            args = [d["fasta_file"], d["blast_dir"], "--db", str(db)]
            if blast_cfg.get("remote"):
                args.append("--remote")
            elif blast_cfg.get("local"):
                args += ["--local", "--threads", str(threads)]
            else:
                args += ["--threads", str(threads)]
            if blast_cfg.get("max_targets"):
                args += ["--max-targets", str(blast_cfg["max_targets"])]
            return args

        case "5b":
            args = [d["blast_tsv"], d["blast_dir"]]
            fetch_cfg = cfg.get("fetch_structures", {})
            if fetch_cfg.get("swissprot_dat"):
                args += ["--swissprot-dat", fetch_cfg["swissprot_dat"]]
            if fetch_cfg.get("no_local_dat"):
                args.append("--no-local-dat")
            if fetch_cfg.get("alphafold_only"):
                args.append("--alphafold-only")
            if fetch_cfg.get("experimental_only"):
                args.append("--experimental-only")
            return args

        case "6":
            return [
                d["colabfold_csv"],
                d["blast_tsv"],
                d["structures_dir"],
                d["reference_dir"],
                d["comparison_dir"],
            ]

        case "7":
            args = [d["results_csv"], d["images_dir"]]
            if Path(d["colabfold_csv"]).exists() or "4" in cfg.get("pipeline", {}).get("steps", []):
                args += ["--colabfold-csv", d["colabfold_csv"]]
            return args

        case "8":
            webapp_cfg = cfg.get("webapp", {})
            args = []
            if webapp_cfg.get("port"):
                args += ["--port", str(webapp_cfg["port"])]
            return args

        case _:
            sys.exit(f"Error: unknown step {step}")


def build_shell_cmd(script: str, args: list[str], env_name: str | None) -> str:
    """Build a shell command string with optional environment activation."""
    cmd_str = " ".join(shlex.quote(str(a)) for a in [f"./{script}"] + args)

    if not env_name:
        return cmd_str

    return f"""\
eval "$(conda shell.bash hook)" 2>/dev/null
if [ -f {shlex.quote(env_name)}/bin/activate ]; then
    source {shlex.quote(env_name)}/bin/activate
else
    conda activate {shlex.quote(env_name)}
fi
{cmd_str}"""


def run_step(
    step: str,
    cfg: dict,
    d: dict,
    dry_run: bool = False,
) -> None:
    """Execute a single pipeline step."""
    script, env_key = STEPS[step]
    env_name = cfg.get("environments", {}).get(env_key) if env_key else None

    # Conditional 5b: skip for pdbaa (Step 5 handles PDB downloads directly)
    if step == "5b":
        blast_db = cfg.get("blast", {}).get("db", "swissprot")
        if blast_db == "pdbaa":
            print(f"  Skipping Step 5b (pdbaa hits have PDB IDs directly)\n")
            return

    args = build_step_args(step, cfg, d)
    shell_cmd = build_shell_cmd(script, args, env_name)

    step_label = f"Step {step}: {STEP_NAMES[step]}"
    env_label = f" (env: {env_name})" if env_name else ""

    print("=" * 60)
    print(f">>> {step_label}{env_label}")
    print("=" * 60)

    if dry_run:
        print(f"  Script: {script}")
        print(f"  Args:   {args}")
        if env_name:
            print(f"  Env:    {env_name}")
        print()
        return

    result = subprocess.run(["bash", "-c", shell_cmd])
    if result.returncode != 0:
        sys.exit(f"\nError: Step {step} failed with exit code {result.returncode}")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Config-driven pipeline runner for BioM3",
        usage="python run_pipeline.py <config.toml> [--steps ...] [--dry-run]",
    )
    parser.add_argument(
        "--version", action="version",
        version=f"%(prog)s {get_version()}",
    )
    parser.add_argument("config", type=Path, help="Path to TOML config file")
    parser.add_argument(
        "--steps", nargs="+", default=None,
        help="Override which steps to run (e.g. --steps 4 5 5b 6 7)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be executed without running anything",
    )
    args = parser.parse_args()

    if not args.config.exists():
        sys.exit(f"Error: config file not found: {args.config}")

    cfg = load_config(args.config)
    d = derive_paths(cfg)

    # Determine which steps to run
    if args.steps:
        steps = [normalize_step_id(s) for s in args.steps]
    else:
        raw_steps = cfg.get("pipeline", {}).get("steps", STEP_ORDER)
        steps = [normalize_step_id(s) for s in raw_steps]

    # Sort steps by canonical order, then append any extras (e.g. step 9)
    ordered = [s for s in STEP_ORDER if s in steps]
    extras = [s for s in steps if s not in STEP_ORDER]
    steps = ordered + extras

    print()
    print(f"BioM3 Pipeline Runner v{get_version()}")
    print("=" * 60)
    print(f"  Config:     {args.config}")
    print(f"  Output dir: {d['output_dir']}")
    print(f"  Steps:      {steps}")
    if args.dry_run:
        print(f"  Mode:       DRY RUN")
    print()

    for step in steps:
        run_step(step, cfg, d, dry_run=args.dry_run)

    print("=" * 60)
    print("Pipeline complete!")
    print(f"Results: {d['output_dir']}/")
    print("=" * 60)


if __name__ == "__main__":
    main()
