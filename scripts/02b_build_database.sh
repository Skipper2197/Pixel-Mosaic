#!/bin/bash
# =============================================================================
# 02b_build_database.sh
# Wraps src/build_database.py: activates the conda environment and builds
# a LAB-color k-d tree from one or more per-dataset thumbnail directories.
# The result is pickled to color_trees/ for use by generate_mosaic.py.
#
# By indexing per-dataset thumbnail subdirectories (e.g. thumbnails/faces/,
# thumbnails/flowers/), different combinations of datasets can each have
# their own pickle without needing to rebuild the full thumbnail library.
#
# Usage:
#   bash scripts/02b_build_database.sh --datasets "DATASET_NAMES" [--pkl-path PATH] [--force]
#
# Options:
#   --datasets "name1 name2 ..."   Space-separated dataset names (required)
#                                  Valid names: faces, flowers, animals
#   --pkl-path PATH                Output path for the pickle (auto-derived
#                                  from --datasets if not given)
#   --force                        Rebuild the pickle even if it already exists
#
# Examples:
#   bash scripts/02b_build_database.sh --datasets "faces"
#   bash scripts/02b_build_database.sh --datasets "flowers animals" --force
#   bash scripts/02b_build_database.sh --datasets "faces flowers animals"
#
# Requirements:
#   - 02_build_thumbnails.sh must have been run for each requested dataset
#   - miniforge3 module available
#
# Inputs:
#   data/thumbnails/<dataset>/  — per-dataset tile directories
# Outputs:
#   color_trees/color_tree_<datasets>.pkl — pickled {'tree': KDTree, 'filenames': [...]}
# =============================================================================

set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

ENV_NAME="mosaic_env"
DATASETS=""                                # required; set by --datasets
PKL_PATH=""                               # auto-derived if not set by --pkl-path
FORCE_FLAG=""                              # populated by --force

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --datasets)
            DATASETS="$2"
            shift 2
            ;;
        --pkl-path)
            PKL_PATH="$2"
            shift 2
            ;;
        --force)
            FORCE_FLAG="--force"
            shift 1
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/02b_build_database.sh --datasets 'DATASET_NAMES' [--pkl-path PATH] [--force]"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate --datasets
# ---------------------------------------------------------------------------
if [[ -z "$DATASETS" ]]; then
    echo "[ERROR] --datasets is required."
    echo "Usage: bash scripts/02b_build_database.sh --datasets 'faces flowers animals' [--force]"
    exit 1
fi

# ---------------------------------------------------------------------------
# Map dataset names to thumbnail subdirectories
# ---------------------------------------------------------------------------
THUMB_DIRS=()
for dataset in $DATASETS; do
    case "$dataset" in
        faces)   THUMB_DIRS+=("$SHARED_DIR/thumbnails/faces") ;;
        flowers) THUMB_DIRS+=("$SHARED_DIR/thumbnails/flowers") ;;
        animals) THUMB_DIRS+=("$SHARED_DIR/thumbnails/animals") ;;
        *)
            echo "[ERROR] Unknown dataset: '$dataset'"
            echo "        Valid names: faces, flowers, animals"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Auto-derive pkl path from dataset names if not explicitly given
# ---------------------------------------------------------------------------
if [[ -z "$PKL_PATH" ]]; then
    DATASETS_SLUG=$(echo "$DATASETS" | tr ' ' '-')
    PKL_PATH="color_trees/color_tree_${DATASETS_SLUG}.pkl"
fi

# ---------------------------------------------------------------------------
# Ensure project root
# ---------------------------------------------------------------------------
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    exit 1
fi

# ---------------------------------------------------------------------------
# Sanity-check each thumbnail directory
# ---------------------------------------------------------------------------
TOTAL_THUMBS=0
for dir in "${THUMB_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        DATASET_NAME=$(basename "$dir")
        echo "[ERROR] $dir does not exist."
        echo "        Run: bash scripts/02_build_thumbnails.sh --dataset $DATASET_NAME"
        exit 1
    fi
    COUNT=$(find "$dir" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | wc -l)
    if [[ "$COUNT" -eq 0 ]]; then
        echo "[ERROR] No thumbnails found in $dir"
        exit 1
    fi
    echo "[01] $dir: $COUNT thumbnails"
    TOTAL_THUMBS=$((TOTAL_THUMBS + COUNT))
done
echo "     Total: $TOTAL_THUMBS thumbnails across ${#THUMB_DIRS[@]} dataset(s)"
echo "     Output: $PKL_PATH"

# ---------------------------------------------------------------------------
# Load miniforge and activate the environment
# (Same pattern as 02_build_thumbnails.sh — see that file for explanation)
# ---------------------------------------------------------------------------
echo "[02] Loading miniforge and initializing conda..."
if command -v module &> /dev/null; then
    module load miniforge3
fi
source "$(conda info --base)/etc/profile.d/conda.sh"

if ! conda info --envs | grep -q "^$ENV_NAME "; then
    echo "[ERROR] Conda environment '$ENV_NAME' not found."
    echo "        Run 02_build_thumbnails.sh first — it creates the env."
    exit 1
fi

echo "[03] Activating $ENV_NAME..."
conda activate "$ENV_NAME"

# ---------------------------------------------------------------------------
# Run the Python stage
#
# "${THUMB_DIRS[@]}" expands the bash array into separate arguments —
# one per dataset directory. build_database.py accepts multiple values
# for --thumb-dir via nargs='+' and combines them into one k-d tree.
#
# Note on $FORCE_FLAG: when --force is NOT passed, FORCE_FLAG is empty
# and we deliberately leave it unquoted so bash drops it entirely from
# the command line rather than passing an empty string argument.
# ---------------------------------------------------------------------------
echo "[04] Running build_database.py..."
python src/build_database.py \
    --thumb-dir "${THUMB_DIRS[@]}" \
    --pkl-path "$PKL_PATH" \
    $FORCE_FLAG

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
if [[ -f "$PKL_PATH" ]]; then
    PKL_SIZE=$(du -h "$PKL_PATH" | cut -f1)
else
    PKL_SIZE="(missing)"
fi

echo ""
echo "============================================================"
echo "  02b_build_database.sh complete"
echo "------------------------------------------------------------"
echo "  Datasets      : $DATASETS"
echo "  Total thumbs  : $TOTAL_THUMBS"
echo "  Database      : $PKL_PATH  ($PKL_SIZE)"
echo "============================================================"
echo ""
echo "Next step: bash scripts/03_generate_mosaic.sh <target> --pkl-path $PKL_PATH"
