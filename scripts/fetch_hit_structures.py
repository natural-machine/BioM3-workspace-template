#!/usr/bin/env python3
"""Fetch reference structures for SwissProt BLAST hits.

For each unique UniProt accession in BLAST results:
  1. Resolve PDB cross-references (from local uniprot_sprot.dat.gz or UniProt API)
  2. Download the best experimental structure from RCSB, or
  3. Fall back to AlphaFold DB predicted structure

Outputs structures as {accession}.pdb so they integrate directly with
Step 7 (07_compare_structures.sh), which extracts the accession from
SwissProt subject IDs via cut -d'|' -f2.
"""

import argparse
import csv
import gzip
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def parse_blast_accessions(blast_tsv: Path) -> list[str]:
    """Extract unique UniProt accessions from BLAST results TSV.

    Expects sseqid in column 2 with format sp|ACCESSION|ENTRY_NAME.
    """
    accessions = set()
    with open(blast_tsv) as f:
        for line in f:
            fields = line.strip().split("\t")
            if len(fields) < 2:
                continue
            parts = fields[1].split("|")
            if len(parts) >= 2:
                accessions.add(parts[1])
    return sorted(accessions)


def lookup_pdb_from_dat(
    accessions: list[str], dat_path: Path
) -> dict[str, list[dict]]:
    """Extract PDB cross-references from local uniprot_sprot.dat.gz.

    Single-pass scan — reads the full file once, tracking only the
    accessions we care about. Typically takes 30-90s for the full
    SwissProt DAT file.
    """
    target = set(accessions)
    remaining = set(accessions)
    results: dict[str, list[dict]] = {acc: [] for acc in accessions}
    current_acc: str | None = None
    in_target = False

    opener = gzip.open if str(dat_path).endswith(".gz") else open
    with opener(dat_path, "rt") as f:
        for line in f:
            if line.startswith("AC   "):
                current_acc = None
                in_target = False
                accs = [a.strip().rstrip(";") for a in line[5:].split(";") if a.strip()]
                for a in accs:
                    if a in target:
                        current_acc = a
                        in_target = True
                        break
            elif in_target and line.startswith("DR   PDB;"):
                # Format: DR   PDB; 6K3G; X-ray; 2.41 A; B=1-360.
                parts = [p.strip().rstrip(".") for p in line[5:].split(";")]
                if len(parts) >= 4:
                    pdb_id = parts[1].strip()
                    method = parts[2].strip()
                    resolution_str = parts[3].strip()
                    try:
                        resolution = float(resolution_str.replace(" A", "").strip())
                    except ValueError:
                        resolution = None
                    results[current_acc].append(
                        {
                            "pdb_id": pdb_id,
                            "method": method,
                            "resolution": resolution,
                        }
                    )
            elif line.startswith("//"):
                if in_target and current_acc:
                    remaining.discard(current_acc)
                    if not remaining:
                        break
                in_target = False
                current_acc = None

    return results


def lookup_pdb_from_api(accessions: list[str]) -> dict[str, list[dict]]:
    """Query UniProt REST API for PDB cross-references."""
    results: dict[str, list[dict]] = {}
    for i, acc in enumerate(accessions):
        url = f"https://rest.uniprot.org/uniprotkb/{acc}.json"
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
            pdb_refs = []
            for xref in data.get("uniProtKBCrossReferences", []):
                if xref.get("database") == "PDB":
                    pdb_id = xref.get("id", "")
                    props = {p["key"]: p["value"] for p in xref.get("properties", [])}
                    method = props.get("Method", "")
                    res_str = props.get("Resolution", "")
                    try:
                        resolution = float(res_str.replace(" A", "").strip())
                    except (ValueError, AttributeError):
                        resolution = None
                    pdb_refs.append(
                        {
                            "pdb_id": pdb_id,
                            "method": method,
                            "resolution": resolution,
                        }
                    )
            results[acc] = pdb_refs
        except urllib.error.HTTPError as e:
            print(f"  Warning: UniProt lookup failed for {acc}: {e}")
            results[acc] = []
        if i < len(accessions) - 1:
            time.sleep(0.2)

    return results


def pick_best_pdb(pdb_refs: list[dict]) -> dict | None:
    """Pick the best PDB entry: prefer X-ray, then lowest resolution."""
    if not pdb_refs:
        return None
    xray = [
        r
        for r in pdb_refs
        if "X-ray" in r.get("method", "") and r["resolution"] is not None
    ]
    if xray:
        return min(xray, key=lambda r: r["resolution"])
    with_res = [r for r in pdb_refs if r["resolution"] is not None]
    if with_res:
        return min(with_res, key=lambda r: r["resolution"])
    return pdb_refs[0]


def download_file(url: str, outpath: Path) -> bool:
    """Download a file, return True on success."""
    try:
        urllib.request.urlretrieve(url, outpath)
        if outpath.stat().st_size > 0:
            return True
        outpath.unlink(missing_ok=True)
    except Exception:
        outpath.unlink(missing_ok=True)
    return False


def download_pdb(pdb_id: str, outpath: Path) -> bool:
    return download_file(f"https://files.rcsb.org/download/{pdb_id}.pdb", outpath)


def download_alphafold(accession: str, outpath: Path) -> bool:
    """Download AlphaFold structure, querying the API for the current version URL."""
    api_url = f"https://alphafold.ebi.ac.uk/api/prediction/{accession}"
    try:
        req = urllib.request.Request(api_url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            entries = json.loads(resp.read())
        if entries and isinstance(entries, list):
            pdb_url = entries[0].get("pdbUrl", "")
            if pdb_url:
                return download_file(pdb_url, outpath)
    except Exception:
        pass
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Fetch reference structures for SwissProt BLAST hits"
    )
    parser.add_argument("blast_tsv", type=Path, help="BLAST results TSV from Step 6")
    parser.add_argument("output_dir", type=Path, help="Output directory for structures")
    parser.add_argument(
        "--swissprot-dat",
        type=Path,
        default=None,
        help="Path to local uniprot_sprot.dat.gz for offline PDB lookup",
    )
    parser.add_argument(
        "--alphafold-only",
        action="store_true",
        help="Skip experimental PDB lookup, download only AlphaFold predictions",
    )
    parser.add_argument(
        "--experimental-only",
        action="store_true",
        help="Skip AlphaFold fallback, download only experimental PDB structures",
    )
    args = parser.parse_args()

    ref_dir = args.output_dir / "reference_structures"
    ref_dir.mkdir(parents=True, exist_ok=True)

    # --- Extract accessions ---
    accessions = parse_blast_accessions(args.blast_tsv)
    if not accessions:
        print("No UniProt accessions found in BLAST results.")
        sys.exit(0)
    print(f"Found {len(accessions)} unique UniProt accessions in BLAST results.\n")

    # --- Resolve PDB cross-references ---
    if args.alphafold_only:
        pdb_mapping: dict[str, list[dict]] = {acc: [] for acc in accessions}
    elif args.swissprot_dat:
        print(f"Scanning {args.swissprot_dat} for PDB cross-references...")
        print("(this may take a minute for the full SwissProt DAT file)\n")
        pdb_mapping = lookup_pdb_from_dat(accessions, args.swissprot_dat)
        n_with_pdb = sum(1 for v in pdb_mapping.values() if v)
        print(f"Found PDB cross-references for {n_with_pdb}/{len(accessions)} accessions.\n")
    else:
        print("Querying UniProt API for PDB cross-references...\n")
        pdb_mapping = lookup_pdb_from_api(accessions)
        n_with_pdb = sum(1 for v in pdb_mapping.values() if v)
        print(f"\nFound PDB cross-references for {n_with_pdb}/{len(accessions)} accessions.\n")

    # --- Download structures ---
    manifest_path = args.output_dir / "structure_manifest.tsv"
    stats = {"experimental": 0, "alphafold": 0, "not_found": 0, "skipped": 0}

    with open(manifest_path, "w", newline="") as mf:
        writer = csv.writer(mf, delimiter="\t")
        writer.writerow(
            ["accession", "source", "pdb_id", "method", "resolution", "filename"]
        )

        print("Downloading structures...")
        for acc in accessions:
            outfile = ref_dir / f"{acc}.pdb"

            if outfile.exists():
                print(f"  {acc}: already exists, skipping")
                stats["skipped"] += 1
                continue

            # Try experimental structure first
            best = pick_best_pdb(pdb_mapping.get(acc, []))
            if best and not args.alphafold_only:
                if download_pdb(best["pdb_id"], outfile):
                    res_str = f"{best['resolution']} A" if best["resolution"] else "N/A"
                    print(
                        f"  {acc}: experimental {best['pdb_id']} ({best['method']}, {res_str})"
                    )
                    writer.writerow(
                        [
                            acc,
                            "experimental",
                            best["pdb_id"],
                            best["method"],
                            best["resolution"] or "",
                            outfile.name,
                        ]
                    )
                    stats["experimental"] += 1
                    continue

            # Fall back to AlphaFold
            if not args.experimental_only:
                if download_alphafold(acc, outfile):
                    print(f"  {acc}: AlphaFold prediction")
                    writer.writerow([acc, "alphafold", "", "", "", outfile.name])
                    stats["alphafold"] += 1
                    continue

            print(f"  {acc}: no structure found")
            writer.writerow([acc, "not_found", "", "", "", ""])
            stats["not_found"] += 1

    print(f"\nSummary:")
    print(f"  Experimental: {stats['experimental']}")
    print(f"  AlphaFold:    {stats['alphafold']}")
    print(f"  Not found:    {stats['not_found']}")
    print(f"  Skipped:      {stats['skipped']}")
    print(f"\nManifest: {manifest_path}")
    print(f"Structures: {ref_dir}/")


if __name__ == "__main__":
    main()
