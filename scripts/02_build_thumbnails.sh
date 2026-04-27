#!/bin/bash
# =============================================================================
# 02_build_thumbnails.sh
# Wraps src/build_thumbnails.py: activates the conda environment (creating
# it from environment.yaml if needed) and resizes images from one dataset
# to 32x32 tiles in a per-dataset subdirectory under data/thumbnails/.
#
# Each dataset gets its own subdirectory so you can mix and match datasets
# without having to delete and rebuild the entire thumbnail library:
#   data/thumbnails/faces/    — faces dataset
#   data/thumbnails/flowers/  — flowers dataset
#   data/thumbnails/animals/  — animals dataset
#
# Usage:
#   bash scripts/02_build_thumbnails.sh --dataset DATASET_NAME [--tile-size N]
#
# Dataset names: faces, flowers, animals
#
# Requirements:
#   - miniforge3 module available (SciClone: module load miniforge3)
#   - environment.yaml present at project root
#   - The corresponding 01_*.sh download script must have run first
#
# Inputs:
#   data/clean/  — validated JPEGs from 01_download_clean.sh / 01b_ / 01c_
# Outputs:
#   data/thumbnails/<dataset>/  — square tiles for this dataset
# =============================================================================

# Taught in class (assignment_05/06)
set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Shared data directory on SciClone scratch storage.
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

ENV_NAME="mosaic_env"                      # must match environment.yaml
SOURCE_DIR="$SHARED_DIR/clean"             # shared clean dir from 01_ / 01b_ / 01c_
TILE_SIZE=32                               # default; overridden by --tile-size
DATASET_NAME=""                            # required; set by --dataset

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dataset)
            DATASET_NAME="$2"
            shift 2
            ;;
        --tile-size)
            TILE_SIZE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/02_build_thumbnails.sh --dataset DATASET_NAME [--tile-size N]"
            echo "       DATASET_NAME: faces, flowers, animals"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required --dataset argument
# ---------------------------------------------------------------------------
if [[ -z "$DATASET_NAME" ]]; then
    echo "[ERROR] --dataset is required."
    echo "Usage: bash scripts/02_build_thumbnails.sh --dataset DATASET_NAME [--tile-size N]"
    echo "       DATASET_NAME: faces, flowers, animals"
    exit 1
fi

# Map dataset name → file prefix (used to filter from shared clean/) and
# thumbnail subdirectory under data/thumbnails/.
case "$DATASET_NAME" in
    faces)
        SOURCE_PREFIX="face_"
        THUMB_SUBDIR="faces"
        ;;
    flowers)
        SOURCE_PREFIX="flower_"
        THUMB_SUBDIR="flowers"
        ;;
    animals)
        SOURCE_PREFIX="animal_"
        THUMB_SUBDIR="animals"
        ;;
    *)
        echo "[ERROR] Unknown dataset: '$DATASET_NAME'"
        echo "        Valid names: faces, flowers, animals"
        exit 1
        ;;
esac

THUMB_DIR="$SHARED_DIR/thumbnails/$THUMB_SUBDIR"

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
    echo "        Run the appropriate 01_*.sh download script first."
    exit 1
fi

CLEAN_COUNT=$(find "$SOURCE_DIR" -maxdepth 1 -iname "${SOURCE_PREFIX}*.jpg" -o \
                                              -iname "${SOURCE_PREFIX}*.jpeg" -o \
                                              -iname "${SOURCE_PREFIX}*.png" 2>/dev/null | wc -l)
if [[ "$CLEAN_COUNT" -eq 0 ]]; then
    echo "[ERROR] No images with prefix '${SOURCE_PREFIX}' found in $SOURCE_DIR."
    echo "        Run the download script for the '$DATASET_NAME' dataset first."
    exit 1
fi
echo "[01] Found $CLEAN_COUNT '$DATASET_NAME' images in $SOURCE_DIR (prefix: '${SOURCE_PREFIX}')"
echo "     Output directory: $THUMB_DIR"

# ---------------------------------------------------------------------------
# Load miniforge and initialize conda — NOT taught in class
#
# On SciClone, conda is provided via a module. 'module load miniforge3'
# puts conda on PATH but does NOT enable the 'conda activate' command
# in the current shell. The second line sources conda's shell hook,
# which defines the shell functions needed for activation.
# ---------------------------------------------------------------------------
echo "[02] Loading miniforge and initializing conda..."
if command -v module &> /dev/null; then
    module load miniforge3
fi
source "$(conda info --base)/etc/profile.d/conda.sh"

# ---------------------------------------------------------------------------
# Create the conda environment if it doesn't exist
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

echo "[05] Running build_thumbnails.py for '$DATASET_NAME'..."
python src/build_thumbnails.py \
    --source-dir "$SOURCE_DIR" \
    --thumb-dir "$THUMB_DIR" \
    --tile-size "$TILE_SIZE" \
    --prefix "$SOURCE_PREFIX"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
THUMB_COUNT=$(find "$THUMB_DIR" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | wc -l)

echo ""
echo "============================================================"
echo "  02_build_thumbnails.sh complete  [$DATASET_NAME]"
echo "------------------------------------------------------------"
echo "  Source prefix : ${SOURCE_PREFIX}*   ($CLEAN_COUNT images)"
echo "  Thumbnails    : $THUMB_DIR/  ($THUMB_COUNT)"
echo "  Tile size     : ${TILE_SIZE}x${TILE_SIZE}"
echo "============================================================"
echo ""
echo "Next step: bash scripts/02b_build_database.sh --datasets '$DATASET_NAME'"
