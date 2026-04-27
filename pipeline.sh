#!/bin/bash
# =============================================================================
# pipeline.sh
# End-to-end orchestrator for the Pixel-Mosaic project.
#
# Runs every stage in order:
#   01_*.sh                — download + clean selected dataset(s)
#   02_build_thumbnails.sh — resize each dataset's images to tiles
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
#     Once the pickle exists, you can generate many different mosaics
#     without rebuilding anything upstream.
#   - Stage 3 is "usage" — it reads the pickle and produces one mosaic
#     per target image. Cheap to re-run.
#   - Each dataset combination gets its own pickle, named automatically
#     from DATASETS (e.g. color_trees/color_tree_faces-flowers.pkl).
#     Switching datasets does not invalidate previously-built pickles.
# =============================================================================

set -ueo pipefail

# ---------------------------------------------------------------------------
# Shared data directory on SciClone scratch storage
# ---------------------------------------------------------------------------
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

# ---------------------------------------------------------------------------
# USER SETTINGS — edit these to change how the pipeline runs
# ---------------------------------------------------------------------------

# Which image datasets to use as mosaic tiles.
# Space-separated list of one or more of: faces, flowers, animals
#   faces   — AI-generated faces (1M Fake Faces dataset, ~15GB)
#   flowers — Flowers-299 dataset
#   animals — Animals-10 dataset
# Examples:
#   DATASETS="faces"                    # faces only
#   DATASETS="flowers animals"          # mix two datasets
#   DATASETS="faces flowers animals"    # use all three
DATASETS="flowers"

# Number of images to keep from each downloaded dataset.
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

# Derive a slug from the dataset list (e.g. "faces flowers" → "faces-flowers")
# and use it to name the pickle. This means each dataset combination gets its
# own file — switching between "flowers" and "flowers animals" doesn't
# require deleting anything.
DATASETS_SLUG=$(echo "$DATASETS" | tr ' ' '-')
PKL_PATH="color_trees/color_tree_${DATASETS_SLUG}.pkl"

echo "============================================================"
echo "  Pixel-Mosaic pipeline"
echo "============================================================"
echo "  Shared dir   : $SHARED_DIR"
echo "  Datasets     : $DATASETS"
echo "  Subset size  : $SUBSET images per dataset"
echo "  Target       : $TARGET"
echo "  Grid         : ${GRID_SIZE}x${GRID_SIZE}"
echo "  Tile         : ${TILE_SIZE}x${TILE_SIZE}"
echo "  Database     : $PKL_PATH"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Stage 1 — download selected datasets
# ---------------------------------------------------------------------------
for dataset in $DATASETS; do
    case "$dataset" in
        faces)
            echo ">>> Stage 1: download faces"
            bash scripts/01_download_clean.sh --subset "$SUBSET"
            ;;
        flowers)
            echo ">>> Stage 1b: download flowers"
            bash scripts/01b_download_flowers.sh --subset "$SUBSET"
            ;;
        animals)
            echo ">>> Stage 1c: download animals"
            bash scripts/01c_download_animals.sh --subset "$SUBSET"
            ;;
        *)
            echo "[ERROR] Unknown dataset: '$dataset'"
            echo "        Valid names: faces, flowers, animals"
            exit 1
            ;;
    esac
    echo ""
done

# ---------------------------------------------------------------------------
# Stage 2 — build thumbnails for each selected dataset
# ---------------------------------------------------------------------------
for dataset in $DATASETS; do
    echo ">>> Stage 2: build thumbnails for '$dataset'"
    bash scripts/02_build_thumbnails.sh --dataset "$dataset" --tile-size "$TILE_SIZE"
    echo ""
done

# ---------------------------------------------------------------------------
# Stage 2b — build the LAB k-d tree over the selected thumbnail directories
# ---------------------------------------------------------------------------
echo ">>> Stage 2b: build LAB k-d tree ($DATASETS)"
bash scripts/02b_build_database.sh --datasets "$DATASETS" --pkl-path "$PKL_PATH"
echo ""

# ---------------------------------------------------------------------------
# Stage 3 — generate the mosaic
# ---------------------------------------------------------------------------
echo ">>> Stage 3: generate mosaic"
bash scripts/03_generate_mosaic.sh "$TARGET" \
    --pkl-path "$PKL_PATH" \
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
echo "  Datasets used : $DATASETS"
echo "  Database      : $PKL_PATH"
echo "  Final mosaic  : $OUTPUT_PATH"
echo "============================================================"
