#!/bin/bash
# =============================================================================
# 01_download_clean.sh
# Downloads a subset of the 1M Fake Faces dataset from Kaggle,
# validates the images with ImageMagick, and merges them into the
# shared data/clean/ directory.
#
# Usage:
#   bash scripts/01_download_clean.sh [--subset N]
#
# Options:
#   --subset N    Keep only N images for local practice (default: 500)
#
# Requirements:
#   - KAGGLE_API_TOKEN environment variable set (see README)
#   - conda environment 'mosaic_env' active (run setup_env.sh first)
#   - ImageMagick and unzip available in the active environment
#
# Outputs:
#   data/raw_faces/  — original downloaded zip and extracted images
#   data/clean/      — validated JPEGs (prefixed with 'face_' to avoid
#                      filename collisions with other sources)
#
# Design note:
#   Previous versions of this script used 'kaggle datasets download --file'
#   to fetch files individually. That code path has a long-standing bug in
#   Kaggle's API (Issue #508 on Kaggle/kaggle-api) which returns 404 for
#   most individual-file downloads even when the same dataset lists fine
#   with 'kaggle datasets files'. The whole-zip download used here avoids
#   that bug entirely — it's Kaggle's well-tested primary path.
# =============================================================================

# Taught in class (assignment_05/06)
set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DATASET="tunguz/1-million-fake-faces-4"   # Kaggle dataset identifier
SUBSET_SIZE=500                            # default images to keep
RAW_DIR="data/raw_faces"                   # source-specific raw dir
CLEAN_DIR="data/clean"                     # SHARED clean dir
LOG_DIR="log"

# Prefix applied when copying into the shared clean/ directory.
# Prevents filename collisions when multiple sources (faces, lhq, etc.)
# feed the same clean directory. See 01b_download_lhq.sh for the
# symmetrical pattern.
FILE_PREFIX="face_"

# ---------------------------------------------------------------------------
# Argument parsing
# See the inline comments in 01b_download_lhq.sh (or an earlier version
# of this script) for a full explanation of $#, case, and shift.
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subset)
            SUBSET_SIZE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: bash scripts/01_download_clean.sh [--subset N]"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Ensure we are running from the project root
# ---------------------------------------------------------------------------
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    echo "        e.g.:  bash scripts/01_download_clean.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo "[01] Creating directory structure..."
mkdir -p "$RAW_DIR" "$CLEAN_DIR" "$LOG_DIR" src

# ---------------------------------------------------------------------------
# Check for the Kaggle API token
# ---------------------------------------------------------------------------
echo "[02] Checking Kaggle API token..."
if [[ -z "${KAGGLE_API_TOKEN:-}" ]]; then
    echo ""
    echo "[ERROR] KAGGLE_API_TOKEN environment variable is not set."
    echo ""
    echo "  To fix this, add the following to your ~/.bashrc:"
    echo "    export KAGGLE_API_TOKEN=your_token_here"
    echo "  Then reload your shell:"
    echo "    source ~/.bashrc"
    echo ""
    echo "  Get your token at: https://www.kaggle.com/settings -> API -> Create New Token"
    echo ""
    exit 1
fi
echo "    Token found."

# ---------------------------------------------------------------------------
# Check that required tools are installed (kaggle, magick, unzip)
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
# Download the dataset as a single zip
#
# 'kaggle datasets download' with NO --file flag downloads the whole
# dataset as a single zip archive. This is Kaggle's primary, well-tested
# download path and it works reliably — unlike 'kaggle datasets download
# --file <path>' which has a long-standing 404 bug on many datasets
# (see Kaggle/kaggle-api#508).
#
# Flags:
#   --path      directory where the zip is saved
#   --force     re-download even if already present
#              (we guard this with our own stamp file below)
#
# Stamp file pattern: write a marker file after success so re-running
# the script skips the download. HPC idempotency pattern from
# assignment_05. The stamp is NOT written unless the downloaded zip
# actually exists on disk — the old "trust the loop's exit code" bug
# cannot recur because we verify the filesystem directly.
#
# Reference: https://www.kaggle.com/docs/api#interacting-with-datasets
# ---------------------------------------------------------------------------
DOWNLOAD_STAMP="$RAW_DIR/.downloaded"
ZIP_FILE="$RAW_DIR/fake-faces.zip"

if [[ -f "$DOWNLOAD_STAMP" && -f "$ZIP_FILE" ]]; then
    echo "[04] Skipping download — stamp file found ($DOWNLOAD_STAMP)."
    echo "     Delete $DOWNLOAD_STAMP to force a re-download."
else
    # If stamp exists but zip doesn't, the previous run lied to us —
    # delete the stamp and re-download cleanly.
    if [[ -f "$DOWNLOAD_STAMP" ]]; then
        echo "[04] Stamp present but zip missing — clearing stale stamp."
        rm "$DOWNLOAD_STAMP"
    fi

    echo "[04] Downloading 1M Fake Faces archive from Kaggle..."
    echo "     (This dataset is several GB — may take a while on first run)"

    kaggle datasets download "$DATASET" \
        --path "$RAW_DIR" \
        --force

    # Kaggle names the zip after the dataset slug. Rename defensively
    # via find rather than hardcoding the exact filename.
    DOWNLOADED_ZIP=$(find "$RAW_DIR" -maxdepth 1 -iname "*.zip" | head -n 1)

    if [[ -z "$DOWNLOADED_ZIP" ]]; then
        echo "[ERROR] No zip file found in $RAW_DIR after download."
        echo "        Check that your Kaggle token is valid and you have"
        echo "        accepted the dataset's terms on kaggle.com."
        exit 1
    fi

    mv "$DOWNLOADED_ZIP" "$ZIP_FILE"

    # "Trust but verify" — only write the stamp after confirming the
    # zip is actually present. This is the lesson from the stale-stamp
    # bug that caused 01_download_clean.sh to report success when
    # nothing had downloaded.
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
# This uses the same pattern as 01b_download_lhq.sh:
#   unzip -Z1 ZIP     list archive contents, one filename per line
#   grep -i '\.jpg$'  keep only .jpg entries
#   head -n N         take the first N
#   xargs ... unzip   extract just those files
#
# The -j flag on unzip flattens paths — files extract directly into
# $RAW_DIR instead of recreating the dataset's internal folder nesting.
# That simplifies the validation loop below (no -maxdepth needed).
#
# Reference: https://linux.die.net/man/1/unzip
# ---------------------------------------------------------------------------
EXTRACT_STAMP="$RAW_DIR/.extracted"

if [[ -f "$EXTRACT_STAMP" ]]; then
    echo "[05] Skipping extraction — stamp file found ($EXTRACT_STAMP)."
    echo "     Delete $EXTRACT_STAMP to force re-extraction."
else
    echo "[05] Extracting first $SUBSET_SIZE images from archive..."

    FILE_LIST="$LOG_DIR/faces_extract_list.txt"

    unzip -Z1 "$ZIP_FILE" \
        | grep -i '\.jpg$' \
        | head -n "$SUBSET_SIZE" \
        > "$FILE_LIST"

    EXTRACT_COUNT=$(wc -l < "$FILE_LIST")
    echo "     Will extract $EXTRACT_COUNT images."

    if [[ "$EXTRACT_COUNT" -eq 0 ]]; then
        echo "[ERROR] No .jpg files found inside $ZIP_FILE."
        exit 1
    fi

    # xargs -a reads arg list from file; -d '\n' splits on newlines
    # (defensive in case a filename ever contains a space)
    # unzip -j flattens output into $RAW_DIR
    # unzip -o overwrites without prompting
    xargs -a "$FILE_LIST" -d '\n' unzip -j -o "$ZIP_FILE" -d "$RAW_DIR" > /dev/null

    touch "$EXTRACT_STAMP"
    echo "     Extraction complete."
fi

# ---------------------------------------------------------------------------
# Count raw images
# -maxdepth 1 because we flattened via unzip -j
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
# Validate images with ImageMagick and copy to shared clean/ with prefix
#
# Same namespace-on-merge pattern as 01b_download_lhq.sh. Output name:
#   raw_faces/00001.jpg  ->  clean/face_00001.jpg
# ---------------------------------------------------------------------------
echo "[07] Validating images with magick identify..."

valid=0
skipped=0
LOG_FILE="$LOG_DIR/01_validation.log"

{
    echo "Faces validation log — target subset: $SUBSET_SIZE"
    echo "Tool: magick identify"
    echo "Output prefix: $FILE_PREFIX"
    echo ""
} > "$LOG_FILE"

for img in $(find "$RAW_DIR" -maxdepth 1 -iname "*.jpg"); do

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
TOTAL_CLEAN=$(find "$CLEAN_DIR" -maxdepth 1 -iname "*.jpg" | wc -l)
FACES_IN_CLEAN=$(find "$CLEAN_DIR" -maxdepth 1 -iname "${FILE_PREFIX}*.jpg" | wc -l)

echo ""
echo "============================================================"
echo "  01_download_clean.sh complete"
echo "------------------------------------------------------------"
echo "  Raw faces         : $RAW_DIR/    ($TOTAL_RAW total)"
echo "  Faces in clean/   : $FACES_IN_CLEAN (prefixed '${FILE_PREFIX}')"
echo "  Clean total       : $CLEAN_DIR/  ($TOTAL_CLEAN images from all sources)"
echo "  Log               : $LOG_FILE"
echo "============================================================"
echo ""
echo "Next step: bash scripts/01b_download_lhq.sh  (optional second source)"
echo "       or: bash scripts/02_build_thumbnails.sh"
