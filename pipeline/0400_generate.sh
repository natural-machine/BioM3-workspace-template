#!/bin/bash
#=============================================================================
# Step 400: Generate Protein Sequences
#
# Uses a finetuned (or pretrained) ProteoScribe model to generate novel
# protein sequences from text prompts. First embeds the input through
# PenCL and Facilitator, then runs ProteoScribe diffusion sampling.
#
# USAGE:
#   ./pipeline/0400_generate.sh <model_weights> <input_csv> <output_dir> [options]
#
# OPTIONS:
#   --pencl_weights PATH                   PenCL model weights
#   --facilitator_weights PATH             Facilitator model weights
#   --pencl_config PATH                    PenCL config JSON
#   --facilitator_config PATH              Facilitator config JSON
#   --proteoscribe_config PATH             ProteoScribe sampling config JSON
#   --batch_size N                         Embedding batch size (default: 256)
#   --dataset_key KEY                      HDF5 dataset key (default: MMD_data)
#   --device DEVICE                        Compute device (default: $BIOM3_DEVICE or cuda)
#   --fasta                                Write per-prompt FASTA files
#   --fasta_merge                          Also write a merged FASTA with all sequences
#   --fasta_dir PATH                       Output directory for FASTA files (default: <output_dir>/fasta/)
#   --unmasking_order {random,confidence,confidence_no_pad}
#                                          Position unmasking order (default: from config)
#   --token_strategy {sample,argmax}       Token selection strategy (default: from config)
#   --animate_prompts IDX [IDX ...]        Prompt indices to animate, 'all', or 'none'
#   --animate_replicas N                   Replicas to animate per prompt (default: 1)
#   --animation_dir PATH                   Output directory for GIF animations
#   --animation_style {brightness,colorbar,logo}
#                                          Probability visualization style (default: brightness)
#   --animation_metrics NAME [NAME ...]    Per-position metric boxes (e.g. confidence)
#   --store_probabilities                  Store per-step probability distributions as .npz
#   --                                     Pass remaining args to biom3_ProteoScribe_sample
#
# EXAMPLE (basic):
#   ./pipeline/0400_generate.sh \
#       outputs/SH3/finetuning/checkpoints/.../state_dict.best.pth \
#       data/SH3/SH3_prompts.csv \
#       outputs/SH3/generation
#
# EXAMPLE (with sampling options and animation):
#   ./pipeline/0400_generate.sh \
#       outputs/SH3/finetuning/checkpoints/.../state_dict.best.pth \
#       data/SH3/SH3_prompts.csv \
#       outputs/SH3/generation \
#       --token_strategy argmax --animate_prompts 0 1 2
#
# EXAMPLE (colored animation with probability storage):
#   ./pipeline/0400_generate.sh \
#       outputs/SH3/finetuning/checkpoints/.../state_dict.best.pth \
#       data/SH3/SH3_prompts.csv \
#       outputs/SH3/generation \
#       --animate_prompts 0 --store_probabilities \
#       --animation_style colorbar --animation_metrics confidence
#
# INPUT:
#   - model_weights: Path to finetuned ProteoScribe weights (.pth, .bin, or .ckpt)
#   - input_csv: CSV with text prompts (same format as Step 2)
#   - output_dir: Directory for generated output
#
# OUTPUT:
#   <output_dir>/<prefix>.ProteoScribe_output.pt
#   <fasta_dir>/prompt_0.fasta, prompt_1.fasta, ...  (if --fasta is used)
#   <fasta_dir>/all_sequences.fasta                  (if --fasta_merge is used)
#   <output_dir>/animations/     (if --animate_prompts is used)
#   <output_dir>/probabilities/  (if --store_probabilities is used)
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <model_weights> <input_csv> <output_dir> [options]"
    echo ""
    echo "Options:"
    echo "  --pencl_weights PATH                   PenCL model weights"
    echo "  --facilitator_weights PATH             Facilitator model weights"
    echo "  --pencl_config PATH                    PenCL config JSON"
    echo "  --facilitator_config PATH              Facilitator config JSON"
    echo "  --proteoscribe_config PATH             ProteoScribe sampling config JSON"
    echo "  --batch_size N                         Embedding batch size (default: 256)"
    echo "  --dataset_key KEY                      HDF5 dataset key (default: MMD_data)"
    echo "  --device DEVICE                        Compute device (default: cuda)"
    echo "  --fasta                                Write per-prompt FASTA files"
    echo "  --fasta_merge                          Write merged FASTA with all sequences"
    echo "  --fasta_dir PATH                       Output directory for FASTA files"
    echo "  --unmasking_order {random,confidence,confidence_no_pad}"
    echo "                                         Position unmasking order"
    echo "  --token_strategy {sample,argmax}       Token selection strategy"
    echo "  --animate_prompts IDX [IDX ...]        Prompt indices to animate"
    echo "  --animate_replicas N                   Replicas to animate (default: 1)"
    echo "  --animation_dir PATH                   Output directory for animations"
    echo "  --animation_style {brightness,colorbar,logo}"
    echo "                                         Probability visualization style"
    echo "  --animation_metrics NAME [NAME ...]    Per-position metric boxes"
    echo "  --store_probabilities                  Store per-step probabilities as .npz"
    echo "  --                                     Pass remaining args to biom3_ProteoScribe_sample"
    echo ""
    echo "Example: $0 outputs/SH3/finetuning/.../state_dict.best.pth data/SH3/prompts.csv outputs/SH3/generation"
    exit 1
fi

model_weights=$1
input_csv=$2
outdir=$3
shift 3

if [ ! -e "${model_weights}" ]; then
    echo "Error: Model weights not found: ${model_weights}"
    exit 1
fi

if [ ! -f "${input_csv}" ]; then
    echo "Error: Input CSV not found: ${input_csv}"
    exit 1
fi

# --- Parse optional flags ---
pencl_weights=""
facilitator_weights=""
pencl_config=""
facilitator_config=""
proteoscribe_config=""
batch_size=""
dataset_key=""
device=""
fasta=false
fasta_merge=false
fasta_dir=""
unmasking_order=""
token_strategy=""
animate_prompts=()
animate_replicas=""
animation_dir=""
animation_style=""
animation_metrics=()
store_probabilities=false
extra_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pencl_weights)
            pencl_weights="$2"
            shift 2
            ;;
        --facilitator_weights)
            facilitator_weights="$2"
            shift 2
            ;;
        --pencl_config)
            pencl_config="$2"
            shift 2
            ;;
        --facilitator_config)
            facilitator_config="$2"
            shift 2
            ;;
        --proteoscribe_config)
            proteoscribe_config="$2"
            shift 2
            ;;
        --batch_size)
            batch_size="$2"
            shift 2
            ;;
        --dataset_key)
            dataset_key="$2"
            shift 2
            ;;
        --device)
            device="$2"
            shift 2
            ;;
        --)
            shift
            extra_args=("$@")
            break
            ;;
        --fasta)
            fasta=true
            shift
            ;;
        --fasta_merge)
            fasta_merge=true
            shift
            ;;
        --fasta_dir)
            fasta_dir="$2"
            shift 2
            ;;
        --unmasking_order)
            unmasking_order="$2"
            shift 2
            ;;
        --token_strategy)
            token_strategy="$2"
            shift 2
            ;;
        --animate_prompts)
            shift
            while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do
                animate_prompts+=("$1")
                shift
            done
            ;;
        --animate_replicas)
            animate_replicas="$2"
            shift 2
            ;;
        --animation_dir)
            animation_dir="$2"
            shift 2
            ;;
        --animation_style)
            animation_style="$2"
            shift 2
            ;;
        --animation_metrics)
            shift
            while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do
                animation_metrics+=("$1")
                shift
            done
            ;;
        --store_probabilities)
            store_probabilities=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

embed_dir="${outdir}/embeddings"
pencl_weights="${pencl_weights:-weights/PenCL/PenCL_V09152023_last.ckpt}"
facilitator_weights="${facilitator_weights:-weights/Facilitator/Facilitator_MMD15.ckpt/last.ckpt}"
pencl_config="${pencl_config:-configs/inference/stage1_PenCL.json}"
facilitator_config="${facilitator_config:-configs/inference/stage2_Facilitator.json}"
proteoscribe_config="${proteoscribe_config:-configs/inference/stage3_ProteoScribe_sample.json}"
batch_size="${batch_size:-256}"
dataset_key="${dataset_key:-MMD_data}"
device="${device:-${BIOM3_DEVICE:-cuda}}"

prefix=$(basename "${input_csv}" .csv)

export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

mkdir -p ${embed_dir} ${outdir}

echo "============================================="
echo "Step 400: Generate Protein Sequences (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Model weights: ${model_weights}"
echo "Input CSV:     ${input_csv}"
echo "Output dir:    ${outdir}"
if [ "${fasta}" = true ]; then echo "FASTA output:    yes"; fi
if [ "${fasta_merge}" = true ]; then echo "FASTA merge:     yes"; fi
if [ -n "${fasta_dir}" ]; then echo "FASTA dir:       ${fasta_dir}"; fi
if [ -n "${unmasking_order}" ]; then echo "Unmasking order: ${unmasking_order}"; fi
if [ -n "${token_strategy}" ]; then echo "Token strategy:  ${token_strategy}"; fi
if [ ${#animate_prompts[@]} -gt 0 ]; then echo "Animate prompts: ${animate_prompts[*]}"; fi
if [ -n "${animate_replicas}" ]; then echo "Animate replicas: ${animate_replicas}"; fi
if [ -n "${animation_dir}" ]; then echo "Animation dir:   ${animation_dir}"; fi
if [ -n "${animation_style}" ]; then echo "Animation style: ${animation_style}"; fi
if [ ${#animation_metrics[@]} -gt 0 ]; then echo "Animation metrics: ${animation_metrics[*]}"; fi
if [ "${store_probabilities}" = true ]; then echo "Store probabilities: yes"; fi
echo ""

# --- Embed input prompts (Stage 1 + Stage 2) ---
echo "[1/2] Embedding input prompts..."
biom3_embedding_pipeline \
    -i ${input_csv} \
    -o ${embed_dir} \
    --pencl_weights ${pencl_weights} \
    --facilitator_weights ${facilitator_weights} \
    --pencl_config ${pencl_config} \
    --facilitator_config ${facilitator_config} \
    --prefix ${prefix} \
    --batch_size ${batch_size} \
    --dataset_key ${dataset_key} \
    --device ${device}

echo "[1/2] Done."
echo ""

# --- ProteoScribe generation ---
echo "[2/2] Generating sequences with ProteoScribe..."
proteoscribe_args=(
    -i "${embed_dir}/${prefix}.Facilitator_emb.pt"
    -c "${proteoscribe_config}"
    -m "${model_weights}"
    -o "${outdir}/${prefix}.ProteoScribe_output.pt"
    --device "${device}"
)

if [ -n "${unmasking_order}" ]; then
    proteoscribe_args+=(--unmasking_order "${unmasking_order}")
fi
if [ -n "${token_strategy}" ]; then
    proteoscribe_args+=(--token_strategy "${token_strategy}")
fi
if [ ${#animate_prompts[@]} -gt 0 ]; then
    proteoscribe_args+=(--animate_prompts "${animate_prompts[@]}")
fi
if [ -n "${animate_replicas}" ]; then
    proteoscribe_args+=(--animate_replicas "${animate_replicas}")
fi
if [ -n "${animation_dir}" ]; then
    proteoscribe_args+=(--animation_dir "${animation_dir}")
fi
if [ -n "${animation_style}" ]; then
    proteoscribe_args+=(--animation_style "${animation_style}")
fi
if [ ${#animation_metrics[@]} -gt 0 ]; then
    proteoscribe_args+=(--animation_metrics "${animation_metrics[@]}")
fi
if [ "${store_probabilities}" = true ]; then
    proteoscribe_args+=(--store_probabilities)
fi
if [ "${fasta}" = true ]; then
    proteoscribe_args+=(--fasta)
fi
if [ "${fasta_merge}" = true ]; then
    proteoscribe_args+=(--fasta_merge)
fi
if [ -n "${fasta_dir}" ]; then
    proteoscribe_args+=(--fasta_dir "${fasta_dir}")
fi

biom3_ProteoScribe_sample "${proteoscribe_args[@]}" "${extra_args[@]}"

echo "[2/2] Done."
echo ""
echo "============================================="
echo "Sequence generation complete."
echo "Output: ${outdir}/${prefix}.ProteoScribe_output.pt"
if [ "${fasta}" = true ]; then
    echo "FASTA:  ${fasta_dir:-${outdir}/fasta}/"
fi
if [ ${#animate_prompts[@]} -gt 0 ]; then
    echo "Animations: ${animation_dir:-${outdir}/animations}/"
fi
if [ "${store_probabilities}" = true ]; then
    echo "Probabilities: ${outdir}/probabilities/"
fi
echo "============================================="
