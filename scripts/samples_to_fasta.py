"""Convert ProteoScribe samples to FASTA format.

Reads a .pt file produced by ProteoScribe generation (Step 3) and writes
one FASTA file per prompt. The number of prompts and replicas is detected
automatically from the .pt file contents.

Usage:
    python scripts/samples_to_fasta.py -i <input.pt> -o <output_pattern>

The output pattern should contain a {} placeholder for the prompt index:
    python scripts/samples_to_fasta.py \
        -i outputs/SH3/generation/SH3_prompts.ProteoScribe_output.pt \
        -o outputs/SH3/samples/SH3_prompts_prompt_{}_samples.fasta
"""

import argparse
import sys

import torch
from Bio import SeqIO
from Bio.Seq import Seq
from Bio.SeqRecord import SeqRecord


def parse_args(args):
    parser = argparse.ArgumentParser(
        description="Convert ProteoScribe .pt output to per-prompt FASTA files"
    )
    parser.add_argument("-i", "--infpath", required=True, type=str,
                        help="Path to .pt file from ProteoScribe generation")
    parser.add_argument("-o", "--outfpath", required=True, type=str,
                        help="Output path pattern with {} for prompt index")
    return parser.parse_args(args)


def main(args):
    infpath = args.infpath
    outfpath = args.outfpath

    input_data = torch.load(infpath, weights_only=False)

    nreplicas = len(input_data)
    nprompts = len(input_data["replica_0"])

    output_data = {f"prompt_{j+1}": [] for j in range(nprompts)}
    for i in range(nreplicas):
        rep = input_data[f"replica_{i}"]
        for j in range(len(rep)):
            output_data[f"prompt_{j+1}"].append(rep[j])

    for j in range(nprompts):
        records = []
        seqs = output_data[f"prompt_{j+1}"]
        for i, seq in enumerate(seqs):
            record = SeqRecord(
                Seq(seq),
                id=f"prompt_{j+1}_replica_{i}",
                description=""
            )
            records.append(record)
        SeqIO.write(records, outfpath.format(j + 1), "fasta")

    print(f"Wrote {nprompts} FASTA files ({nreplicas} replicas each)")


if __name__ == "__main__":
    args = parse_args(sys.argv[1:])
    main(args)
