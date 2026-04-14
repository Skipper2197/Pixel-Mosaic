#!/bin/bash
# =============================================================================
# 02_build_thumbnails.sh
# Wraps src/build_thumbnails.py: activates the conda environment (creating
# it from environment.yaml if needed) and resizes every image in data/clean
# to 32x32 tiles stored in data/thumbnails.
#
# Usage:
#   bash scripts/02_build_thumbnails.sh [--tile-size N]
#
# Requirements:
#   - miniforge3 module available (SciClone: module load miniforge3)
#   - environment.yaml present at project root
#
# Inputs:
#   data/clean/        — validated JPEGs from 01_download_clean.sh / 01b_
# Outputs:
#   data/thumbnails/   — square tiles ready for build_database.py
# =============================================================================

# Taught in class (assignment_05/06)
set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ENV_NAME="mosaic_env"                      # must match environment.yaml
SOURCE_DIR="data/clean"                    # shared clean dir from 01_ / 01b_
THUMB_DIR="data/thumbnails"
TILE_SIZE=32                               # default; overridden by --tile-size

# ---------------------------------------------------------------------------
# Argument parsing — same pattern as 01_download_clean.sh
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tile-size)
            TILE_SIZE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/02_build_thumbnails.sh [--tile-size N]"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Ensure project root
# ---------------------------------------------------------------------------
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    exit 1
fi

# ---------------------------------------------------------------------------
# Sanity check the clean directory BEFORE bothering with conda
# Fast-fail is cheaper than waiting for environment activation first.
# ---------------------------------------------------------------------------
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "[ERROR] $SOURCE_DIR does not exist."
    echo "        Run 01_download_clean.sh (and optionally 01b_download_lhq.sh) first."
    exit 1
fi

CLEAN_COUNT=$(find "$SOURCE_DIR" -maxdepth 1 -iname "*.jpg" | wc -l)
if [[ "$CLEAN_COUNT" -eq 0 ]]; then
    echo "[ERROR] No images found in $SOURCE_DIR."
    exit 1
fi
echo "[01] Found $CLEAN_COUNT cleaned images in $SOURCE_DIR"

# ---------------------------------------------------------------------------
# Load miniforge and initialize conda — NOT taught in class
#
# On SciClone, conda is provided via a module. 'module load miniforge3'
# puts conda on PATH but does NOT enable the 'conda activate' command
# in the current shell. The second line sources conda's shell hook,
# which defines the shell functions needed for activation.
#
# Reference: https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html
# This pattern was taken directly from the assignment_07 SLURM script.
# ---------------------------------------------------------------------------
echo "[02] Loading miniforge and initializing conda..."
# 'module' only exists on HPC systems like SciClone. On a laptop with
# miniforge installed directly, conda is already on PATH and we just
# need to source the shell hook. Same portable pattern as the
# 'command -v kaggle' check in 01_download_clean.sh.
if command -v module &> /dev/null; then
    module load miniforge3
fi
source "$(conda info --base)/etc/profile.d/conda.sh"

# ---------------------------------------------------------------------------
# Create the conda environment if it doesn't exist — NOT taught in class
#
# 'conda info --envs' lists all environments. We grep for our name to
# decide whether to create or reuse. Creating from environment.yaml
# (rather than listing packages inline like the SLURM file does) means
# the single source of truth for dependencies is one file on disk —
# which is what reproducibility actually means.
#
# 'mamba env create' is used in preference to 'conda env create' because
# miniforge3 ships with mamba and it's significantly faster at solving
# environments. Fall back to conda if mamba is unavailable.
#
# Reference: https://mamba.readthedocs.io/
# ---------------------------------------------------------------------------
echo "[03] Checking conda environment '$ENV_NAME'..."
if conda info --envs | grep -q "^$ENV_NAME "; then
    echo "     Environment '$ENV_NAME' already exists."
else
    echo "     Environment '$ENV_NAME' not found. Creating from environment.yaml..."
    if [[ ! -f "environment.yaml" ]]; then
        echo "[ERROR] environment.yaml not found at project root."
        exit 1
    fi

    # Prefer mamba (faster solver) but fall back to conda if unavailable
    if command -v mamba &> /dev/null; then
        mamba env create -f environment.yaml
    else
        conda env create -f environment.yaml
    fi
fi

# ---------------------------------------------------------------------------
# Activate the environment and run the Python stage
# ---------------------------------------------------------------------------
echo "[04] Activating $ENV_NAME..."
conda activate "$ENV_NAME"

echo "[05] Running build_thumbnails.py..."
python src/build_thumbnails.py \
    --source-dir "$SOURCE_DIR" \
    --thumb-dir "$THUMB_DIR" \
    --tile-size "$TILE_SIZE"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
THUMB_COUNT=$(find "$THUMB_DIR" -maxdepth 1 -iname "*.jpg" | wc -l)

echo ""
echo "============================================================"
echo "  02_build_thumbnails.sh complete"
echo "------------------------------------------------------------"
echo "  Source images : $SOURCE_DIR     ($CLEAN_COUNT)"
echo "  Thumbnails    : $THUMB_DIR/     ($THUMB_COUNT)"
echo "  Tile size     : ${TILE_SIZE}x${TILE_SIZE}"
echo "============================================================"
echo ""
echo "Next step: bash scripts/02b_build_database.sh"
