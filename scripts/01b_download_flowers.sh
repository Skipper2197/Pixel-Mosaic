#!/bin/bash
# =============================================================================
# 01b_download_flowers.sh
# Downloads a subset of the Flowers-299 dataset from Kaggle, validates
# the images with ImageMagick, and merges them into the shared
# data/clean/ directory with the 'flower_' prefix.
#
# This script follows the exact same pattern as 01_download_clean.sh —
# see that file for detailed comments on each step. The only
# differences are:
#   - DATASET, RAW_DIR, FILE_PREFIX, ZIP_FILE name
#   - grep also matches .png (some flower datasets include PNGs)
#
# Usage:
#   bash scripts/01b_download_flowers.sh [--subset N]
#
# Options:
#   --subset N    Keep only N images (default: 5000)
#
# Outputs:
#   data/raw_flowers/  — downloaded zip and extracted images
#   data/clean/        — validated images (prefixed 'flower_')
# =============================================================================

# Taught in class (assignment_05/06)
set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

DATASET="bogdancretu/flower299"            # Kaggle dataset identifier
SUBSET_SIZE=5000                           # default images to keep
RAW_DIR="$SHARED_DIR/raw_flowers"          # source-specific raw dir
CLEAN_DIR="$SHARED_DIR/clean"              # SHARED clean dir
LOG_DIR="log"

# Prefix prevents filename collisions when multiple sources
# (faces, flowers, animals) feed the same clean directory.
FILE_PREFIX="flower_"

# ---------------------------------------------------------------------------
# Argument parsing — same pattern as 01_download_clean.sh
#
# $# is the count of positional arguments passed to the script.
# 'case' matches the current argument against known flags.
# 'shift 2' moves past both the flag (--subset) and its value (N),
# so the while loop advances to the next argument pair.
# '*' is the catch-all: any unrecognized flag triggers an error.
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subset)
            SUBSET_SIZE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/01b_download_flowers.sh [--subset N]"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Ensure we are running from the project root
# ---------------------------------------------------------------------------
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    echo "        e.g.:  bash scripts/01b_download_flowers.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo "[01] Creating directory structure..."
mkdir -p "$RAW_DIR" "$CLEAN_DIR" "$LOG_DIR"

# ---------------------------------------------------------------------------
# Check for the Kaggle API token
# ---------------------------------------------------------------------------
echo "[02] Checking Kaggle API token..."
if [[ -z "${KAGGLE_API_TOKEN:-}" ]]; then
    echo "[ERROR] KAGGLE_API_TOKEN environment variable is not set."
    exit 1
fi
echo "    Token found."

# ---------------------------------------------------------------------------
# Check that required tools are installed
# ---------------------------------------------------------------------------
echo "[03] Checking required tools..."
for tool in kaggle magick unzip; do
    if ! command -v "$tool" &> /dev/null; then
        echo "[ERROR] '$tool' command not found."
        echo "        Activate your conda environment: conda activate mosaic_env"
        exit 1
    fi
done
echo "    kaggle, magick, and unzip found."

# ---------------------------------------------------------------------------
# Download the dataset
# ---------------------------------------------------------------------------
DOWNLOAD_STAMP="$RAW_DIR/.downloaded"
ZIP_FILE="$RAW_DIR/flowers.zip"

if [[ -f "$DOWNLOAD_STAMP" && -f "$ZIP_FILE" ]]; then
    echo "[04] Skipping download — stamp file found ($DOWNLOAD_STAMP)."
else
    if [[ -f "$DOWNLOAD_STAMP" ]]; then
        echo "[04] Stamp present but zip missing — clearing stale stamp."
        rm "$DOWNLOAD_STAMP"
    fi

    echo "[04] Downloading Flowers-299 archive from Kaggle..."

    kaggle datasets download "$DATASET" \
        --path "$RAW_DIR" \
        --force

    DOWNLOADED_ZIP=$(find "$RAW_DIR" -maxdepth 1 -iname "*.zip" | head -n 1)

    if [[ -z "$DOWNLOADED_ZIP" ]]; then
        echo "[ERROR] No zip file found in $RAW_DIR after download."
        exit 1
    fi

    mv "$DOWNLOADED_ZIP" "$ZIP_FILE"

    if [[ -f "$ZIP_FILE" ]]; then
        touch "$DOWNLOAD_STAMP"
        echo "     Download complete: $ZIP_FILE"
    else
        echo "[ERROR] Zip file missing after rename. Not writing stamp."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Extract only the first SUBSET_SIZE images from the zip
#
# Two-step listing avoids the SIGPIPE bug under pipefail — see
# the comment in 01_download_clean.sh for the full explanation.
# ---------------------------------------------------------------------------
EXTRACT_STAMP="$RAW_DIR/.extracted"

if [[ -f "$EXTRACT_STAMP" ]]; then
    echo "[05] Skipping extraction — stamp file found ($EXTRACT_STAMP)."
else
    echo "[05] Extracting first $SUBSET_SIZE images from archive..."

    FILE_LIST="$LOG_DIR/flowers_extract_list.txt"

    # Two-step to avoid SIGPIPE under pipefail (see 01_download_clean.sh)
    unzip -Z1 "$ZIP_FILE" \
        | grep -iE '\.(jpg|jpeg|png)$' \
        > "${FILE_LIST}.full"
    head -n "$SUBSET_SIZE" "${FILE_LIST}.full" > "$FILE_LIST"
    rm -f "${FILE_LIST}.full"

    EXTRACT_COUNT=$(wc -l < "$FILE_LIST")
    echo "     Will extract $EXTRACT_COUNT images."

    if [[ "$EXTRACT_COUNT" -eq 0 ]]; then
        echo "[ERROR] No image files found inside $ZIP_FILE."
        exit 1
    fi

    xargs -a "$FILE_LIST" -d '\n' unzip -j -o "$ZIP_FILE" -d "$RAW_DIR" > /dev/null

    touch "$EXTRACT_STAMP"
    echo "     Extraction complete."
fi

# ---------------------------------------------------------------------------
# Count raw images
# ---------------------------------------------------------------------------
TOTAL_RAW=$(find "$RAW_DIR" -maxdepth 1 \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
    | wc -l)
echo "[06] Raw images found: $TOTAL_RAW"

if [[ "$TOTAL_RAW" -eq 0 ]]; then
    echo "[ERROR] No images found in $RAW_DIR after extraction."
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate images and copy to shared clean/ with prefix
# ---------------------------------------------------------------------------
echo "[07] Validating images with magick identify..."

valid=0
skipped=0
LOG_FILE="$LOG_DIR/01b_flowers_validation.log"

{
    echo "Flowers validation log — target subset: $SUBSET_SIZE"
    echo "Tool: magick identify"
    echo "Output prefix: $FILE_PREFIX"
    echo ""
} > "$LOG_FILE"

for img in $(find "$RAW_DIR" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \)); do

    if ! magick identify "$img" &> /dev/null; then
        echo "SKIP  $(basename "$img") — failed magick identify" >> "$LOG_FILE"
        ((skipped++)) || true
        continue
    fi

    out_name="${FILE_PREFIX}$(basename "$img")"
    cp "$img" "$CLEAN_DIR/$out_name"

    echo "OK    $out_name" >> "$LOG_FILE"
    ((valid++)) || true

done

{
    echo ""
    echo "Result: $valid valid, $skipped corrupt/skipped"
} >> "$LOG_FILE"

echo "    Valid images cleaned : $valid"
echo "    Corrupt/skipped      : $skipped"
echo "    Validation log       : $LOG_FILE"

if [[ "$valid" -eq 0 ]]; then
    echo "[ERROR] No valid images were cleaned. Check $LOG_FILE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
TOTAL_CLEAN=$(find "$CLEAN_DIR" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l)
FLOWERS_IN_CLEAN=$(find "$CLEAN_DIR" -maxdepth 1 -iname "${FILE_PREFIX}*" | wc -l)

echo ""
echo "============================================================"
echo "  01b_download_flowers.sh complete"
echo "------------------------------------------------------------"
echo "  Raw flowers       : $RAW_DIR/    ($TOTAL_RAW total)"
echo "  Flowers in clean/ : $FLOWERS_IN_CLEAN (prefixed '${FILE_PREFIX}')"
echo "  Clean total       : $CLEAN_DIR/  ($TOTAL_CLEAN images from all sources)"
echo "  Log               : $LOG_FILE"
echo "============================================================"
echo ""
echo "Next step: bash scripts/01c_download_animals.sh  (optional)"
echo "       or: bash scripts/02_build_thumbnails.sh"
