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
    "100": ("pipeline/0100_build_dataset.sh",       "biom3"),
    "200": ("pipeline/0200_embedding.sh",           "biom3"),
    "300": ("pipeline/0300_finetune.sh",             "biom3"),
    "400": ("pipeline/0400_generate.sh",             "biom3"),
    "500": ("pipeline/0500_colabfold.sh",            "colabfold"),
    "600": ("pipeline/0600_blast_search.sh",         "blast"),
    "610": ("pipeline/0610_fetch_hit_structures.sh", None),
    "700": ("pipeline/0700_compare_structures.sh",   "biom3"),
    "800": ("pipeline/0800_plot_results.sh",          "biom3"),
    "900": ("pipeline/0900_webapp.sh",               "biom3"),
}

# Step 900 (webapp) is interactive/blocking — excluded from default order.
# Use --steps 900 to launch it explicitly.
STEP_ORDER = ["100", "200", "300", "400", "500", "600", "610", "700", "800"]

STEP_NAMES = {
    "100": "Build Dataset",
    "200": "Embedding",
    "300": "Finetuning",
    "400": "Generation",
    "500": "ColabFold Structure Prediction",
    "600": "BLAST Search",
    "610": "Fetch Reference Structures",
    "700": "Structure Comparison (TMalign)",
    "800": "Plot Results",
    "900": "Web App",
}

# Step ID → TOML section name for step-specific config
STEP_SECTIONS = {
    "100": "build_dataset",
    "200": "embedding",
    "300": "finetuning",
    "400": "generation",
    "500": "colabfold",
    "600": "blast",
    "610": "fetch_structures",
    "700": "comparison",
    "800": "plotting",
    "900": "webapp",
}

# Step ID → (subdir name, paths dict key) for variant output dirs
STEP_SUBDIRS = {
    "100": ("dataset",     "dataset_dir"),
    "200": ("embeddings",  "embeddings_dir"),
    "300": ("finetuning",  "finetuning_dir"),
    "400": ("generation",  "generation_dir"),
    "500": ("structures",  "structures_dir"),
    "600": ("blast",       "blast_dir"),
    "610": ("blast",       "blast_dir"),
    "700": ("comparison",  "comparison_dir"),
    "800": ("images",      "images_dir"),
    "900": (None,          None),
}


def normalize_step_id(s) -> str:
    """Normalize a step ID to its canonical string form."""
    s = str(s).lower().strip()
    if s in STEPS:
        return s
    sys.exit(f"Error: invalid step ID '{s}'. Valid: {list(STEPS.keys())}")


def parse_step_spec(spec) -> tuple[str, str | None]:
    """Parse a step spec like '400.random' into (step_id, variant_filter).

    Returns (step_id, None) for plain step IDs like '400' or '610'.
    """
    spec = str(spec).strip()
    if "." in spec:
        step_id, variant = spec.split(".", 1)
        return normalize_step_id(step_id), variant
    return normalize_step_id(spec), None


def get_step_variants(step: str, cfg: dict) -> list[dict]:
    """Return list of variant configs for a step.

    Handles both single [section] (dict) and [[section]] (list of dicts).
    Returns [{}] if the step has no config section.
    """
    section = STEP_SECTIONS.get(step)
    if not section:
        return [{}]

    raw = cfg.get(section)
    if raw is None:
        return [{}]
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        return [raw]
    return [{}]


def validate_variants(cfg: dict) -> None:
    """Check that variant names within each step section are unique."""
    for step, section in STEP_SECTIONS.items():
        raw = cfg.get(section)
        if not isinstance(raw, list):
            continue
        names = [v.get("variant", "default") for v in raw]
        seen = set()
        for name in names:
            if name in seen:
                sys.exit(
                    f"Error: duplicate variant name '{name}' in "
                    f"[[{section}]] (step {step})"
                )
            seen.add(name)


def derive_variant_paths(base_d: dict, step: str, variant_cfg: dict) -> dict:
    """Compute per-variant path overrides from a variant config.

    If the variant has an explicit output_dir, use it for the step's primary
    directory. If it has a variant name, auto-derive a suffixed subdir.
    Recomputes dependent downstream paths accordingly.
    """
    vd = dict(base_d)
    variant_name = variant_cfg.get("variant", "default")

    subdir_info = STEP_SUBDIRS.get(step)
    if not subdir_info or subdir_info[0] is None:
        return vd

    subdir_name, dir_key = subdir_info

    # Override the step's primary output directory
    variant_outdir = variant_cfg.get("output_dir")
    if variant_outdir:
        vd[dir_key] = variant_outdir
    elif variant_name != "default":
        vd[dir_key] = f"{base_d['output_dir']}/{subdir_name}_{variant_name}"

    # Recompute downstream paths that depend on step-specific dirs
    if step == "200":
        vd["hdf5_file"] = (
            f"{vd['embeddings_dir']}/{base_d['input_prefix']}.compiled_emb.hdf5"
        )

    elif step == "400":
        # samples_dir is a sibling of generation_dir
        if variant_outdir:
            vd["samples_dir"] = variant_cfg.get(
                "samples_dir", f"{variant_outdir}/samples"
            )
        elif variant_name != "default":
            vd["samples_dir"] = f"{base_d['output_dir']}/samples_{variant_name}"
        vd["fasta_file"] = f"{vd['samples_dir']}/all_sequences.fasta"
        vd["pt_file"] = (
            f"{vd['generation_dir']}/"
            f"{base_d['prompts_prefix']}.ProteoScribe_output.pt"
        )

    elif step in ("600", "610"):
        vd["blast_tsv"] = f"{vd['blast_dir']}/blast_hit_results.tsv"
        vd["reference_dir"] = f"{vd['blast_dir']}/reference_structures"

    elif step == "500":
        vd["colabfold_csv"] = f"{vd['structures_dir']}/colabfold_results.csv"

    elif step == "700":
        vd["results_csv"] = f"{vd['comparison_dir']}/results.csv"

    # Allow explicit path overrides from variant config
    for key in ("hdf5_file", "fasta_file", "blast_tsv", "reference_dir",
                "colabfold_csv", "results_csv", "samples_dir",
                "structures_dir", "blast_dir", "comparison_dir", "images_dir"):
        if key in variant_cfg:
            vd[key] = variant_cfg[key]

    return vd


def get_step_outputs(step: str, d: dict) -> list[str]:
    """Return expected output paths for a step, given its resolved paths dict."""
    prefix = d.get("input_prefix", "")
    prompts_prefix = d.get("prompts_prefix", "")

    match step:
        case "100":
            return [
                f"{d['input_csv']}",
            ]
        case "200":
            return [
                f"{d['embeddings_dir']}/{prefix}.PenCL_emb.pt",
                f"{d['embeddings_dir']}/{prefix}.Facilitator_emb.pt",
                f"{d['embeddings_dir']}/{prefix}.compiled_emb.hdf5",
                f"{d['embeddings_dir']}/build_manifest.json",
                f"{d['embeddings_dir']}/run.log",
            ]
        case "300":
            return [
                f"{d['finetuning_dir']}/checkpoints/<run_id>/state_dict.best.pth",
                f"{d['finetuning_dir']}/runs/<run_id>/metrics.json",
            ]
        case "400":
            return [
                f"{d['generation_dir']}/{prompts_prefix}.ProteoScribe_output.pt",
                f"{d['samples_dir']}/all_sequences.fasta",
                f"{d['samples_dir']}/<prompt_N_samples>.fasta",
            ]
        case "500":
            return [
                f"{d['structures_dir']}/colabfold_results.csv",
                f"{d['structures_dir']}/prompt_<i>/*.pdb",
            ]
        case "600":
            return [
                f"{d['blast_dir']}/blast_hit_results.tsv",
            ]
        case "610":
            return [
                f"{d['blast_dir']}/structure_manifest.tsv",
                f"{d['blast_dir']}/reference_structures/<accession>.pdb",
            ]
        case "700":
            return [
                f"{d['comparison_dir']}/results.csv",
                f"{d['comparison_dir']}/logs/*.TMalign.log",
            ]
        case "800":
            return [
                f"{d['images_dir']}/TM_scores.png",
                f"{d['images_dir']}/RMSD_scores.png",
                f"{d['images_dir']}/seqID_scores.png",
                f"{d['images_dir']}/pLDDT_scores.png",
            ]
        case "900":
            return []
        case _:
            return []


def _build_tree(paths: list[str], root: str) -> dict:
    """Build a nested dict tree from a list of file paths under a common root."""
    tree: dict = {}
    for path in paths:
        # Make relative to root
        if path.startswith(root):
            rel = path[len(root):]
        else:
            rel = path
        rel = rel.lstrip("/")
        parts = rel.split("/")
        node = tree
        for part in parts:
            if part not in node:
                node[part] = {}
            node = node[part]
    return tree


def _render_tree(tree: dict, prefix: str = "") -> list[str]:
    """Render a nested dict tree as lines with box-drawing characters."""
    lines = []
    items = list(tree.items())
    for i, (name, subtree) in enumerate(items):
        is_last = i == len(items) - 1
        connector = "\u2514\u2500\u2500 " if is_last else "\u251c\u2500\u2500 "
        lines.append(f"{prefix}{connector}{name}")
        extension = "    " if is_last else "\u2502   "
        lines.extend(_render_tree(subtree, prefix + extension))
    return lines


def print_output_tree(output_root: str, all_outputs: list[str]) -> None:
    """Print a tree of expected output paths."""
    if not all_outputs:
        return
    print()
    print("Expected output tree:")
    print(f"{output_root}/")
    tree = _build_tree(sorted(set(all_outputs)), output_root)
    for line in _render_tree(tree):
        print(f"  {line}")
    print()


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

    # Derive prefix from input_csv (Steps 200-300) or prompts_csv (Steps 400+)
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

    # HDF5 from Step 200
    d["hdf5_file"] = paths.get(
        "hdf5_file",
        f"{d['embeddings_dir']}/{input_prefix}.compiled_emb.hdf5"
    )

    # Model weights from Step 300 (auto-detect if not set)
    d["model_weights"] = paths.get("model_weights", "")

    # .pt file from Step 400
    d["pt_file"] = paths.get(
        "pt_file",
        f"{d['generation_dir']}/{prompts_prefix}.ProteoScribe_output.pt"
    )

    # Epochs (optional override for Step 300)
    d["epochs"] = paths.get("epochs", "")

    # FASTA from Step 400 (--fasta_merge output)
    d["fasta_file"] = f"{d['samples_dir']}/all_sequences.fasta"

    # Reference structures from Step 600/610
    d["reference_dir"] = f"{d['blast_dir']}/reference_structures"

    # ColabFold results from Step 500
    d["colabfold_csv"] = f"{d['structures_dir']}/colabfold_results.csv"

    # BLAST results from Step 600
    d["blast_tsv"] = f"{d['blast_dir']}/blast_hit_results.tsv"

    # TMalign results from Step 700
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


def _append_extra_args(args: list[str], variant_cfg: dict) -> list[str]:
    """Append extra_args passthrough from variant config."""
    extra = variant_cfg.get("extra_args", [])
    if extra:
        args += ["--"] + [str(x) for x in extra]
    return args


def build_step_args(
    step: str, cfg: dict, d: dict, variant_cfg: dict | None = None,
) -> list[str]:
    """Build the CLI argument list for a given step script."""
    vc = variant_cfg or {}

    match step:
        case "100":
            args = [d["input_csv"]]
            return _append_extra_args(args, vc)

        case "200":
            args = [d["input_csv"], d["embeddings_dir"]]
            for flag in ("pencl_weights", "facilitator_weights",
                         "pencl_config", "facilitator_config",
                         "batch_size", "dataset_key", "device"):
                if vc.get(flag):
                    args += [f"--{flag}", str(vc[flag])]
            return _append_extra_args(args, vc)

        case "300":
            args = [d["hdf5_file"], d["finetuning_dir"]]
            if d["epochs"]:
                args.append(str(d["epochs"]))
            if vc.get("config"):
                args += ["--config", vc["config"]]
            if vc.get("device"):
                args += ["--device", str(vc["device"])]
            return args

        case "400":
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
            # Model/inference overrides
            for flag in ("pencl_weights", "facilitator_weights",
                         "pencl_config", "facilitator_config",
                         "proteoscribe_config", "batch_size",
                         "dataset_key", "device"):
                if vc.get(flag):
                    args += [f"--{flag}", str(vc[flag])]
            # Generation-specific options
            if vc.get("unmasking_order"):
                args += ["--unmasking_order", vc["unmasking_order"]]
            if vc.get("token_strategy"):
                args += ["--token_strategy", vc["token_strategy"]]
            if vc.get("animate_prompts"):
                args += ["--animate_prompts"] + [
                    str(x) for x in vc["animate_prompts"]
                ]
            if vc.get("animate_replicas"):
                args += ["--animate_replicas", str(vc["animate_replicas"])]
            if vc.get("animation_dir"):
                args += ["--animation_dir", vc["animation_dir"]]
            if vc.get("animation_style"):
                args += ["--animation_style", vc["animation_style"]]
            if vc.get("animation_metrics"):
                args += ["--animation_metrics"] + [
                    str(x) for x in vc["animation_metrics"]
                ]
            if vc.get("store_probabilities"):
                args += ["--store_probabilities"]
            return _append_extra_args(args, vc)

        case "500":
            return [d["samples_dir"], d["structures_dir"]]

        case "600":
            db = vc.get("db", "swissprot")
            threads = vc.get("threads", 16)
            args = [d["fasta_file"], d["blast_dir"], "--db", str(db)]
            if vc.get("remote"):
                args.append("--remote")
            elif vc.get("local"):
                args += ["--local", "--threads", str(threads)]
            else:
                args += ["--threads", str(threads)]
            if vc.get("max_targets"):
                args += ["--max-targets", str(vc["max_targets"])]
            return args

        case "610":
            args = [d["blast_tsv"], d["blast_dir"]]
            if vc.get("swissprot_dat"):
                args += ["--swissprot-dat", vc["swissprot_dat"]]
            if vc.get("no_local_dat"):
                args.append("--no-local-dat")
            if vc.get("alphafold_only"):
                args.append("--alphafold-only")
            if vc.get("experimental_only"):
                args.append("--experimental-only")
            return args

        case "700":
            return [
                d["colabfold_csv"],
                d["blast_tsv"],
                d["structures_dir"],
                d["reference_dir"],
                d["comparison_dir"],
            ]

        case "800":
            args = [d["results_csv"], d["images_dir"]]
            if Path(d["colabfold_csv"]).exists() or "500" in cfg.get("pipeline", {}).get("steps", []):
                args += ["--colabfold-csv", d["colabfold_csv"]]
            return args

        case "900":
            args = []
            if vc.get("port"):
                args += ["--port", str(vc["port"])]
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
    variant_cfg: dict | None = None,
    dry_run: bool = False,
) -> None:
    """Execute a single pipeline step."""
    vc = variant_cfg or {}
    script, env_key = STEPS[step]
    env_name = cfg.get("environments", {}).get(env_key) if env_key else None

    # Conditional 610: skip for pdbaa (Step 600 handles PDB downloads directly)
    if step == "610":
        blast_db = vc.get("db", "swissprot")
        if blast_db == "pdbaa":
            print(f"  Skipping Step 5b (pdbaa hits have PDB IDs directly)\n")
            return

    args = build_step_args(step, cfg, d, vc)
    shell_cmd = build_shell_cmd(script, args, env_name)

    variant_name = vc.get("variant")
    step_label = f"Step {step}: {STEP_NAMES[step]}"
    if variant_name:
        step_label += f" [{variant_name}]"
    env_label = f" (env: {env_name})" if env_name else ""

    print("=" * 60)
    print(f">>> {step_label}{env_label}")
    print("=" * 60)

    if dry_run:
        print(f"  Script:  {script}")
        print(f"  Args:    {args}")
        if env_name:
            print(f"  Env:     {env_name}")
        if variant_name:
            print(f"  Variant: {variant_name}")
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
        help=(
            "Override which steps to run "
            "(e.g. --steps 4 5 5b 6 7 or --steps 3.random 3.confidence 4)"
        ),
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be executed without running anything",
    )
    args = parser.parse_args()

    if not args.config.exists():
        sys.exit(f"Error: config file not found: {args.config}")

    cfg = load_config(args.config)
    validate_variants(cfg)
    d = derive_paths(cfg)

    # Parse step specs (may include variant filters like "3.random")
    if args.steps:
        step_specs = args.steps
    else:
        step_specs = cfg.get("pipeline", {}).get("steps", STEP_ORDER)

    # Normalize and sort by canonical order
    parsed = [parse_step_spec(s) for s in step_specs]
    base_ids = [step_id for step_id, _ in parsed]
    ordered = [(s, v) for s, v in parsed if s in STEP_ORDER]
    ordered.sort(key=lambda sv: STEP_ORDER.index(sv[0]))
    extras = [(s, v) for s, v in parsed if s not in STEP_ORDER]
    parsed = ordered + extras

    # Display step summary (show variant filters if any)
    step_labels = []
    for step_id, vfilter in parsed:
        step_labels.append(f"{step_id}.{vfilter}" if vfilter else step_id)

    print()
    print(f"BioM3 Pipeline Runner v{get_version()}")
    print("=" * 60)
    print(f"  Config:     {args.config}")
    print(f"  Output dir: {d['output_dir']}")
    print(f"  Steps:      {step_labels}")
    if args.dry_run:
        print(f"  Mode:       DRY RUN")
    print()

    # Track active contexts for fan-out across multi-variant steps.
    # Each context is (variant_name, paths_dict).
    active_contexts: list[tuple[str, dict]] = [("default", d)]
    all_outputs: list[str] = []  # collect expected outputs for dry-run tree

    for step_id, variant_filter in parsed:
        variants = get_step_variants(step_id, cfg)
        has_explicit_variants = any(v.get("variant") for v in variants)

        # Apply variant filter if specified (e.g. "3.random")
        if variant_filter:
            variants = [
                v for v in variants if v.get("variant") == variant_filter
            ]
            if not variants:
                sys.exit(
                    f"Error: variant '{variant_filter}' not found for "
                    f"step {step_id}"
                )

        if has_explicit_variants:
            # This step defines its own variants — they become the new
            # active context set (replacement, not multiplication).
            new_contexts = []
            for vc in variants:
                vname = vc.get("variant", "default")
                vd = derive_variant_paths(d, step_id, vc)
                run_step(step_id, cfg, vd, vc, dry_run=args.dry_run)
                all_outputs.extend(get_step_outputs(step_id, vd))
                new_contexts.append((vname, vd))
            active_contexts = new_contexts

        else:
            # No explicit variants. Check fan_out toggle.
            single_cfg = variants[0] if variants else {}
            if single_cfg.get("fan_out") is False:
                # Collapse: run once with base paths
                run_step(step_id, cfg, d, single_cfg, dry_run=args.dry_run)
                all_outputs.extend(get_step_outputs(step_id, d))
                active_contexts = [("default", d)]
            else:
                # Inherit: run once per active context.
                # Suffix this step's output dir with the context variant
                # name so that each fan-out variant gets its own directory.
                new_contexts = []
                for ctx_name, ctx_paths in active_contexts:
                    step_paths = ctx_paths
                    if ctx_name != "default":
                        inherited_vc = {"variant": ctx_name}
                        step_paths = derive_variant_paths(
                            ctx_paths, step_id, inherited_vc,
                        )
                    run_step(
                        step_id, cfg, step_paths, single_cfg,
                        dry_run=args.dry_run,
                    )
                    all_outputs.extend(get_step_outputs(step_id, step_paths))
                    new_contexts.append((ctx_name, step_paths))
                active_contexts = new_contexts

    if args.dry_run:
        print_output_tree(d["output_dir"], all_outputs)

    print("=" * 60)
    print("Pipeline complete!")
    print(f"Results: {d['output_dir']}/")
    print("=" * 60)


if __name__ == "__main__":
    main()
