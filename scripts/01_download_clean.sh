#!/bin/bash
# =============================================================================
# 01_download_clean.sh
# Downloads a small subset of the 1M Fake Faces dataset from Kaggle,
# validates the images with ImageMagick, and organizes them into
# raw/ and clean/ directories.
#
# Usage:
#   bash scripts/01_download_clean.sh [--subset N]
#
# Options:
#   --subset N    Keep only N images for local practice (default: 500)
#
# Requirements:
#   - KAGGLE_API_TOKEN environment variable set (see README)
#   - conda environment 'mosaic-env' active (run setup_env.sh first)
#   - ImageMagick available in the active environment
#
# Outputs:
#   data/raw/       — original downloaded images (untouched)
#   data/clean/     — validated, non-corrupt JPEGs ready for thumbnailing
# =============================================================================

# Taught in class (assignment_05/06): exits immediately on any error,
# unset variable, or failed pipe.
set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration — taught in class: variables use ALL_CAPS by convention
# ---------------------------------------------------------------------------
DATASET="tunguz/1-million-fake-faces-4"  # Kaggle dataset identifier (owner/dataset-name)
SUBSET_SIZE=500                           # default images to keep for local practice
RAW_DIR="data/raw"
CLEAN_DIR="data/clean"
THUMB_DIR="data/thumbnails"
LOG_DIR="log"

# ---------------------------------------------------------------------------
# Argument parsing — NOT taught in class
#
# $# is a special bash variable that holds the number of arguments passed
# to the script. We loop while there are still arguments left to read.
#
# 'case' works like a switch statement — it matches $1 (the current argument)
# against patterns and runs the matching block.
#
# 'shift N' discards the first N positional arguments, sliding the rest
# down so $2 becomes $1, etc. We shift 2 after --subset because we consume
# both the flag ("--subset") and its value ("500") at once.
#
# Reference: https://www.gnu.org/software/bash/manual/bash.html#Special-Parameters
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --subset)
            SUBSET_SIZE="$2"
            shift 2          # consume both --subset and the number after it
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
# Taught in class: -f tests whether a regular file exists
# ---------------------------------------------------------------------------
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    echo "        e.g.:  bash scripts/01_download_clean.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Create directory structure — taught in class: mkdir -p makes parent dirs
# ---------------------------------------------------------------------------
echo "[01] Creating directory structure..."
mkdir -p "$RAW_DIR" "$CLEAN_DIR" "$THUMB_DIR" "$LOG_DIR" src

# ---------------------------------------------------------------------------
# Check for the Kaggle API token — NOT fully taught in class
#
# Kaggle's newer CLI uses an environment variable (KAGGLE_API_TOKEN) instead
# of a JSON credentials file. We check whether the variable is set and
# non-empty using bash parameter expansion:
#
#   ${VARIABLE:-}   means "use $VARIABLE, or an empty string if unset"
#
# This is needed because set -u would cause an error if we referenced an
# unset variable directly. The -z flag tests whether a string is empty.
#
# Reference: https://www.kaggle.com/docs/api#authentication
# ---------------------------------------------------------------------------
echo "[02] Checking Kaggle API token..."
if [[ -z "${KAGGLE_API_TOKEN:-}" ]]; then
    echo ""
    echo "[ERROR] KAGGLE_API_TOKEN environment variable is not set."
    echo ""
    echo "  To fix this, add the following to your ~/.bashrc (or ~/.zshrc on Mac):"
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
# Check that required tools are installed and on PATH — NOT taught in class
#
# 'command -v' is the POSIX-standard way to test whether a command exists
# on your PATH. It prints the full path if found, nothing if not found.
# We redirect both stdout and stderr to /dev/null so nothing prints to
# the terminal — we only care about the exit code (0 = found, 1 = not found).
#
#   &>  redirects both stdout (1) and stderr (2) simultaneously
#   /dev/null is a special file that discards everything written to it
#
# We loop over both tools so we catch all missing dependencies at once
# rather than failing one at a time.
#
# Reference: https://www.gnu.org/software/bash/manual/bash.html#Bash-Builtins
# ---------------------------------------------------------------------------
echo "[03] Checking required tools..."
for tool in kaggle magick; do
    if ! command -v "$tool" &> /dev/null; then
        echo "[ERROR] '$tool' command not found."
        echo "        Activate your conda environment: conda activate mosaic-env"
        exit 1
    fi
done
echo "    kaggle and magick found."

# ---------------------------------------------------------------------------
# Get the list of files in the dataset — NOT taught in class
#
# This dataset has no zip archive — files are individual JPEGs nested inside
# folders. We use 'kaggle datasets files' to retrieve the full file listing,
# then extract just the file paths (column 1) and filter to JPEGs only.
#
# Flags used:
#   --csv     output as comma-separated values so we can reliably parse it
#             (default output is a human-readable table with variable spacing)
#
# Pipeline breakdown:
#   tail -n +2        skip the CSV header row (name,size,creationDate)
#   cut -d',' -f1     extract only the first column (the file path)
#   grep -i '\.jpg'   keep only JPEG filenames (case-insensitive)
#   head -n N         take only the first N paths for our practice subset
#
# Reference: https://www.kaggle.com/docs/api#interacting-with-datasets
# ---------------------------------------------------------------------------
echo "[04] Fetching file list from Kaggle (this may take a moment)..."

FILE_LIST="$LOG_DIR/kaggle_file_list.txt"

kaggle datasets files "$DATASET" --csv \
    | tail -n +2 \
    | cut -d',' -f1 \
    | grep -i '\.jpg' \
    | head -n "$SUBSET_SIZE" \
    > "$FILE_LIST"

AVAILABLE=$(wc -l < "$FILE_LIST")
echo "    Found $AVAILABLE files to download (requested: $SUBSET_SIZE)"

if [[ "$AVAILABLE" -eq 0 ]]; then
    echo "[ERROR] No files found in dataset listing. Check your Kaggle token and dataset name."
    exit 1
fi

# ---------------------------------------------------------------------------
# Download each file individually — NOT taught in class
#
# Because the dataset contains no zip, we loop over each path in our list
# and download them one at a time using 'kaggle datasets download --file'.
#
# Stamp file pattern: we write a stamp after all downloads complete so
# that re-running the script skips the download entirely. This is the same
# HPC pattern used in assignment_05 to avoid re-running expensive steps.
#
# 'kaggle datasets download --file' flags:
#   --file     path of a single file within the dataset to download
#   --path     local directory to place the downloaded file
#   --quiet    suppress progress bar output
#   --force    overwrite if the file already exists locally
#
# Reference: https://www.kaggle.com/docs/api#interacting-with-datasets
# ---------------------------------------------------------------------------
DOWNLOAD_STAMP="$RAW_DIR/.downloaded"

if [[ -f "$DOWNLOAD_STAMP" ]]; then
    echo "[05] Skipping download — stamp file found ($DOWNLOAD_STAMP)."
    echo "     Delete $DOWNLOAD_STAMP to force a re-download."
else
    echo "[05] Downloading $AVAILABLE images to $RAW_DIR/..."
    count=0
    while IFS= read -r filepath; do
        kaggle datasets download "$DATASET" \
            --file "$filepath" \
            --path "$RAW_DIR" \
            --quiet \
            --force

        ((count++)) || true

        # Print progress every 50 files so we know it's still running
        if (( count % 50 == 0 )); then
            echo "     Downloaded $count / $AVAILABLE"
        fi
    done < "$FILE_LIST"

    echo "     Download complete: $count files."
    touch "$DOWNLOAD_STAMP"
fi

# ---------------------------------------------------------------------------
# Count raw images — NOT fully taught in class
#
# 'find' was introduced in class but these flags are new:
#   -maxdepth 3   look up to 3 levels deep to catch files in subfolders
#   -iname        case-insensitive name match ("*.JPG" matches "*.jpg" too)
#   -o            logical OR between -iname patterns (must be wrapped in \( \))
#
# 'wc -l' counts lines in the output — one filename per line = image count.
#
# Reference: https://man7.org/linux/man-pages/man1/find.1.html
# ---------------------------------------------------------------------------
TOTAL_RAW=$(find "$RAW_DIR" -maxdepth 3 \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
    | wc -l)
echo "[06] Raw images found: $TOTAL_RAW"

if [[ "$TOTAL_RAW" -eq 0 ]]; then
    echo "[ERROR] No images found in $RAW_DIR after download."
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate images using ImageMagick — NOT taught in class
#
# 'magick identify' reads an image file and prints its properties
# (format, dimensions, color depth, etc.). Crucially, it returns a
# non-zero exit code if the file is corrupt or unreadable, making it
# a reliable validator. We only care about the exit code, so we
# redirect output to /dev/null.
#
# If the file passes validation we copy it as-is with 'cp'. There is
# no need to re-encode here because 02_build_database.sh will resize
# every image to 32x32, which normalizes them at that stage.
#
# Reference: https://imagemagick.org/script/identify.php
# ---------------------------------------------------------------------------
echo "[07] Validating images with magick identify..."

valid=0
skipped=0
LOG_FILE="$LOG_DIR/01_validation.log"

{
    echo "Validation log — target subset: $SUBSET_SIZE"
    echo "Tool: magick identify"
    echo ""
} > "$LOG_FILE"

# Taught in class: for loop iterating over output of a subshell command
for img in $(find "$RAW_DIR" -maxdepth 3 -iname "*.jpg"); do

    # Run magick identify; skip the file if it returns a non-zero exit code
    if ! magick identify "$img" &> /dev/null; then
        echo "SKIP  $(basename "$img") — failed magick identify" >> "$LOG_FILE"
        ((skipped++)) || true
        continue
    fi

    # File is valid — copy it as-is to data/clean/
    cp "$img" "$CLEAN_DIR/$(basename "$img")"

    echo "OK    $(basename "$img")" >> "$LOG_FILE"
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
CLEAN_COUNT=$(find "$CLEAN_DIR" -maxdepth 1 -iname "*.jpg" | wc -l)

echo ""
echo "============================================================"
echo "  01_download_clean.sh complete"
echo "------------------------------------------------------------"
echo "  Raw images   : $RAW_DIR/    ($TOTAL_RAW total)"
echo "  Clean images : $CLEAN_DIR/  ($CLEAN_COUNT ready)"
echo "  Log          : $LOG_FILE"
echo "============================================================"
echo ""
echo "Next step: bash scripts/02_build_database.sh"
