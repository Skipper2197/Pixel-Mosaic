#!/bin/bash
# =============================================================================
# 02b_build_database.sh
# Wraps src/build_database.py: activates the conda environment and builds
# a LAB-color k-d tree from the thumbnails produced by 02_build_thumbnails.sh.
# The result is pickled to data/color_tree.pkl for use by generate_mosaic.py.
#
# Usage:
#   bash scripts/02b_build_database.sh [--force]
#
# Options:
#   --force    Rebuild the pickle even if it already exists
#
# Requirements:
#   - 02_build_thumbnails.sh must have been run first
#   - miniforge3 module available
#
# Inputs:
#   data/thumbnails/   — square tiles from 02_build_thumbnails.sh
# Outputs:
#   data/color_tree.pkl — pickled {'tree': KDTree, 'filenames': [...]}
# =============================================================================

set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Shared data directory on SciClone scratch storage.
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

ENV_NAME="mosaic_env"
THUMB_DIR="$SHARED_DIR/thumbnails"
PKL_PATH="$SHARED_DIR/color_tree.pkl"
FORCE_FLAG=""                              # populated by --force

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_FLAG="--force"
            shift 1
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/02b_build_database.sh [--force]"
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
# Sanity-check the thumbnail directory
# ---------------------------------------------------------------------------
if [[ ! -d "$THUMB_DIR" ]]; then
    echo "[ERROR] $THUMB_DIR does not exist."
    echo "        Run 02_build_thumbnails.sh first."
    exit 1
fi

THUMB_COUNT=$(find "$THUMB_DIR" -maxdepth 1 -iname "*.jpg" | wc -l)
if [[ "$THUMB_COUNT" -eq 0 ]]; then
    echo "[ERROR] No thumbnails found in $THUMB_DIR."
    echo "        Run 02_build_thumbnails.sh first."
    exit 1
fi
echo "[01] Found $THUMB_COUNT thumbnails in $THUMB_DIR"

# ---------------------------------------------------------------------------
# Load miniforge and activate the environment
# (Same pattern as 02_build_thumbnails.sh — see that file for explanation)
# ---------------------------------------------------------------------------
echo "[02] Loading miniforge and initializing conda..."
# See 02_build_thumbnails.sh for the explanation of this pattern.
if command -v module &> /dev/null; then
    module load miniforge3
fi
source "$(conda info --base)/etc/profile.d/conda.sh"

# The environment should already exist from 02_. If it doesn't, the
# user is running scripts out of order — tell them so instead of
# silently building it again.
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
# Note on the $FORCE_FLAG expansion:
#   When --force is NOT passed, FORCE_FLAG is the empty string and
#   we need bash to drop it entirely from the command line (not pass
#   an empty argument). Unquoted expansion of an empty variable
#   produces no argument, which is exactly what we want here — this
#   is one of the rare cases where you deliberately don't quote.
# ---------------------------------------------------------------------------
echo "[04] Running build_database.py..."
python src/build_database.py \
    --thumb-dir "$THUMB_DIR" \
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
echo "  Thumbnails    : $THUMB_DIR/     ($THUMB_COUNT)"
echo "  Database      : $PKL_PATH       ($PKL_SIZE)"
echo "============================================================"
echo ""
echo "Next step: bash scripts/03_generate_mosaic.sh"
