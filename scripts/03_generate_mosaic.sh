#!/bin/bash
# =============================================================================
# 03_generate_mosaic.sh
# Wraps src/generate_mosaic.py: activates the conda environment and
# builds a photomosaic of the target image using the k-d tree database
# produced by 02b_build_database.sh.
#
# Usage:
#   bash scripts/03_generate_mosaic.sh <target-image> [--grid-size N] [--tile-size N]
#
# Arguments:
#   <target-image>   Path to the image you want to reproduce as a mosaic
#                    (positional, required). Example: data/target/rock.jpg
#
# Options:
#   --grid-size N    Number of cells per side (default: 100)
#   --tile-size N    Tile edge length in pixels (default: 32)
#
# Requirements:
#   - 02b_build_database.sh must have been run first (needs the pickle)
#   - miniforge3 available (on SciClone; optional locally)
#
# Inputs:
#   data/color_tree.pkl  — pickled k-d tree from 02b_build_database.sh
#   <target-image>       — any image file readable by PIL
# Outputs:
#   output/mosaic_<target-name>.jpg — the generated mosaic, auto-named
#                                     from the target filename
#
# Naming example:
#   bash 03_generate_mosaic.sh data/target/rock.webp
#   → output/mosaic_rock.jpg
# =============================================================================

set -ueo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Shared data directory on SciClone scratch storage.
SHARED_DIR="/sciclone/scr10/gzdata440/Pixel-Mosaic/data"

ENV_NAME="mosaic_env"
PKL_PATH="$SHARED_DIR/color_tree.pkl"
OUTPUT_DIR="output"
GRID_SIZE=100                              # defaults; overridden by flags
TILE_SIZE=32

# ---------------------------------------------------------------------------
# Argument parsing — mixing positional and optional args
#
# This is a slight variation on the pattern used in 01_/02_. Those scripts
# only had flags. Here we have ONE required positional argument (the
# target image path) plus optional flags. The strategy:
#
#   1. Walk through all args
#   2. If it starts with "--", treat as a flag (consume flag + value)
#   3. Otherwise, treat as the positional target (only accept one)
#
# This lets the user pass args in any order:
#   bash 03_generate_mosaic.sh rock.jpg --grid-size 50
#   bash 03_generate_mosaic.sh --grid-size 50 rock.jpg
# Both work.
# ---------------------------------------------------------------------------
TARGET_IMAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --grid-size)
            GRID_SIZE="$2"
            shift 2
            ;;
        --tile-size)
            TILE_SIZE="$2"
            shift 2
            ;;
        --*)
            echo "Unknown flag: $1"
            echo "Usage: bash scripts/03_generate_mosaic.sh <target-image> [--grid-size N] [--tile-size N]"
            exit 1
            ;;
        *)
            # Positional arg. Only accept one — reject if we already have a target.
            if [[ -n "$TARGET_IMAGE" ]]; then
                echo "[ERROR] Multiple positional arguments given: '$TARGET_IMAGE' and '$1'"
                echo "        Only one target image is allowed per run."
                exit 1
            fi
            TARGET_IMAGE="$1"
            shift 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required positional argument
# ---------------------------------------------------------------------------
if [[ -z "$TARGET_IMAGE" ]]; then
    echo "[ERROR] No target image specified."
    echo ""
    echo "Usage:"
    echo "  bash scripts/03_generate_mosaic.sh <target-image> [--grid-size N] [--tile-size N]"
    echo ""
    echo "Example:"
    echo "  bash scripts/03_generate_mosaic.sh data/target/rock.jpg"
    exit 1
fi

# ---------------------------------------------------------------------------
# Ensure project root
# ---------------------------------------------------------------------------
if [[ ! -f "pipeline.sh" ]]; then
    echo "[ERROR] Please run this script from the Pixel-Mosaic project root."
    exit 1
fi

# ---------------------------------------------------------------------------
# Sanity-check inputs BEFORE bothering with conda
# ---------------------------------------------------------------------------
if [[ ! -f "$TARGET_IMAGE" ]]; then
    echo "[ERROR] Target image not found: $TARGET_IMAGE"
    exit 1
fi
echo "[01] Target image: $TARGET_IMAGE"

if [[ ! -f "$PKL_PATH" ]]; then
    echo "[ERROR] Database pickle not found: $PKL_PATH"
    echo "        Run 02b_build_database.sh first."
    exit 1
fi
echo "    Database      : $PKL_PATH"

# ---------------------------------------------------------------------------
# Derive the output filename from the target's basename
#
# This uses two bash parameter expansions:
#
#   ${path##*/}       strip everything up to and including the last slash
#                     (equivalent to `basename`, done inline)
#                     data/target/rock.webp → rock.webp
#
#   ${name%.*}        strip the shortest suffix matching ".*"
#                     (strips the final extension)
#                     rock.webp → rock
#
# Combined, they turn any target path into a clean stem we can use
# in the output filename. This is the same pattern used in assignment_05
# for deriving trimmed filenames from raw reads (${FWD/_R1_/_R2_}).
#
# Reference: https://www.gnu.org/software/bash/manual/bash.html#Shell-Parameter-Expansion
# ---------------------------------------------------------------------------
TARGET_BASENAME="${TARGET_IMAGE##*/}"      # rock.webp
TARGET_STEM="${TARGET_BASENAME%.*}"        # rock
OUTPUT_PATH="${OUTPUT_DIR}/mosaic_${TARGET_STEM}.jpg"

echo "    Output        : $OUTPUT_PATH"
echo "    Grid          : ${GRID_SIZE}x${GRID_SIZE}"
echo "    Tile          : ${TILE_SIZE}x${TILE_SIZE}"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Load miniforge and activate the environment
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
# ---------------------------------------------------------------------------
echo "[04] Running generate_mosaic.py..."
python src/generate_mosaic.py \
    --pkl-path "$PKL_PATH" \
    --target "$TARGET_IMAGE" \
    --output "$OUTPUT_PATH" \
    --grid-size "$GRID_SIZE" \
    --tile-size "$TILE_SIZE"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
if [[ -f "$OUTPUT_PATH" ]]; then
    OUTPUT_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
else
    OUTPUT_SIZE="(missing)"
fi

echo ""
echo "============================================================"
echo "  03_generate_mosaic.sh complete"
echo "------------------------------------------------------------"
echo "  Target        : $TARGET_IMAGE"
echo "  Database      : $PKL_PATH"
echo "  Grid          : ${GRID_SIZE}x${GRID_SIZE} (${TILE_SIZE}px tiles)"
echo "  Output        : $OUTPUT_PATH ($OUTPUT_SIZE)"
echo "============================================================"
echo ""
echo "Open the output with your image viewer to see the result."
