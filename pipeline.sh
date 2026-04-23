#!/bin/bash
# =============================================================================
# pipeline.sh
# End-to-end orchestrator for the Pixel-Mosaic project.
#
# Runs every stage in order:
#   01_download_clean.sh   — download + clean fake faces dataset
#   02_build_thumbnails.sh — resize every clean image to a 32x32 tile
#   02b_build_database.sh  — build a LAB-color k-d tree over the tiles
#   03_generate_mosaic.sh  — produce a mosaic of the target image
#
# Usage:
#   bash pipeline.sh
#
# To change what gets produced, edit the USER SETTINGS section below.
# Every stage is idempotent — re-running pipeline.sh will skip any
# work that has already been done (downloads, thumbnails, and the
# pickle are all guarded by stamps or existence checks). Only the
# final mosaic is regenerated every run, because that's typically
# what the user is iterating on.
#
# Design notes:
#   - Stages 1-2b are "setup" — they produce the reusable tile library.
#     Once the pickle exists at data/color_tree.pkl, you can generate
#     many different mosaics without rebuilding anything upstream.
#   - Stage 3 is "usage" — it reads the pickle and produces one mosaic
#     per target image. Cheap to re-run.
#   - If you want a new mosaic from a different target image, the
#     fastest path is to edit TARGET below and re-run pipeline.sh, OR
#     to call scripts/03_generate_mosaic.sh directly with the new path.
# =============================================================================

set -ueo pipefail

# ---------------------------------------------------------------------------
# Shared data directory on SciClone scratch storage
# ---------------------------------------------------------------------------
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

# ---------------------------------------------------------------------------
# USER SETTINGS — edit these to change how the pipeline runs
# ---------------------------------------------------------------------------

# Number of images to keep from the downloaded dataset.
# Small values (100-1000) are good for local testing.
# Large values (10000+) produce better-looking mosaics on the HPC.
SUBSET=500

# Path to the target image you want to reproduce as a mosaic.
# The output will be auto-named from this file's basename, e.g.:
#   .../dwayne-johnson-walk-of-fame-honor.webp → output/mosaic_dwayne-johnson-walk-of-fame-honor.jpg
TARGET="$SHARED_DIR/target/dwayne-johnson-walk-of-fame-honor.webp"

# Mosaic grid and tile size (passed through to 03_generate_mosaic.sh).
# Defaults match the project spec.
GRID_SIZE=100
TILE_SIZE=32

# ---------------------------------------------------------------------------
# Everything below here is orchestration. You shouldn't need to edit it.
# ---------------------------------------------------------------------------

# Sanity check — refuse to run from anywhere except the project root
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    echo "        cd to the directory containing pipeline.sh, then:"
    echo "          bash pipeline.sh"
    exit 1
fi

# Sanity check — make sure the target image actually exists before
# going through the whole setup only to fail at the last stage.
if [[ ! -f "$TARGET" ]]; then
    echo "[ERROR] Target image not found: $TARGET"
    echo "        Edit the TARGET variable at the top of pipeline.sh"
    echo "        or place your target image at that path."
    exit 1
fi

echo "============================================================"
echo "  Pixel-Mosaic pipeline"
echo "============================================================"
echo "  Shared dir   : $SHARED_DIR"
echo "  Subset size  : $SUBSET images"
echo "  Target       : $TARGET"
echo "  Grid         : ${GRID_SIZE}x${GRID_SIZE}"
echo "  Tile         : ${TILE_SIZE}x${TILE_SIZE}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Stage 1 — fake faces download
# ---------------------------------------------------------------------------
echo ">>> Stage 1: download fake faces"
bash scripts/01_download_clean.sh --subset "$SUBSET"
echo ""

# ---------------------------------------------------------------------------
# Stage 1b — flowers download
# ---------------------------------------------------------------------------
echo ">>> Stage 1b: download flowers"
bash scripts/01b_download_flowers.sh --subset "$SUBSET"
echo ""

# ---------------------------------------------------------------------------
# Stage 1c — animals download
# ---------------------------------------------------------------------------
echo ">>> Stage 1c: download animals"
bash scripts/01c_download_animals.sh --subset "$SUBSET"
echo ""

# ---------------------------------------------------------------------------
# Stage 2 — thumbnail the shared clean directory
# ---------------------------------------------------------------------------
echo ">>> Stage 2: build 32x32 thumbnails"
bash scripts/02_build_thumbnails.sh --tile-size "$TILE_SIZE"
echo ""

# ---------------------------------------------------------------------------
# Stage 2b — build the LAB k-d tree
# ---------------------------------------------------------------------------
echo ">>> Stage 2b: build LAB k-d tree"
bash scripts/02b_build_database.sh
echo ""

# ---------------------------------------------------------------------------
# Stage 3 — generate the mosaic
# ---------------------------------------------------------------------------
echo ">>> Stage 3: generate mosaic"
bash scripts/03_generate_mosaic.sh "$TARGET" \
    --grid-size "$GRID_SIZE" \
    --tile-size "$TILE_SIZE"
echo ""

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
TARGET_BASENAME="${TARGET##*/}"
TARGET_STEM="${TARGET_BASENAME%.*}"
OUTPUT_PATH="output/mosaic_${TARGET_STEM}.jpg"

echo "============================================================"
echo "  Pipeline complete"
echo "------------------------------------------------------------"
echo "  Final mosaic : $OUTPUT_PATH"
echo "============================================================"
