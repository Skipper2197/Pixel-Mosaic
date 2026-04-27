"""
build_thumbnails.py
Resize every image in a source directory to a fixed tile size and
save the results to a thumbnail directory.

This is stage 1 of the database build. It exists as a separate script
(rather than a function call inside build_database.py) because
thumbnailing is the slow, idempotent step: it only needs to run once
per raw dataset, and the thumbnails can be reused across many
database rebuilds if you tweak the LAB math.

Usage:
    python src/build_thumbnails.py \\
        --source-dir data/clean \\
        --thumb-dir data/thumbnails \\
        --tile-size 32

Idempotency:
    Files that already exist in --thumb-dir are skipped. Delete the
    thumbnail directory (or individual files) to force a rebuild.
    This matches the stamp-file pattern used in 01_download_clean.sh.
"""

import argparse
import os
import sys

from PIL import Image
from tqdm import tqdm

# Allow "python src/build_thumbnails.py" to find common.py as a sibling
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import DEFAULT_TILE_SIZE, list_images


def build_thumbnails(source_dir, thumb_dir, tile_size, prefix=""):
    """
    Iterate over source_dir, write tile_size x tile_size versions to
    thumb_dir. Skip any file that already exists in thumb_dir.

    If prefix is given, only process files whose names start with that
    string (e.g. 'face_', 'flower_'). This lets multiple datasets share
    a single clean/ directory while thumbnailing each independently.

    Why resize twice (thumbnail then resize)?
        PIL's .thumbnail() preserves aspect ratio — a 1024x768 input
        becomes 32x24, not 32x32. We then force an exact square with
        .resize() so the k-d tree sees uniform tiles. Doing both
        avoids unnecessary upscaling when the input is already small.
    """
    if not os.path.isdir(source_dir):
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    os.makedirs(thumb_dir, exist_ok=True)

    all_files = list_images(source_dir)
    raw_files = [f for f in all_files if not prefix or f.startswith(prefix)]
    if not raw_files:
        qualifier = f" matching prefix '{prefix}'" if prefix else ""
        raise ValueError(f"No images found{qualifier} in {source_dir}")

    qualifier = f" matching prefix '{prefix}'" if prefix else ""
    print(f"Checking/creating {tile_size}x{tile_size} thumbnails "
          f"for {len(raw_files)} images{qualifier}...")

    created = 0
    skipped_existing = 0
    failed = 0

    for filename in tqdm(raw_files, desc="Thumbnailing"):
        source_path = os.path.join(source_dir, filename)
        thumb_path = os.path.join(thumb_dir, filename)

        # Idempotency — skip if already thumbnailed
        if os.path.exists(thumb_path):
            skipped_existing += 1
            continue

        try:
            with Image.open(source_path) as img:
                img = img.convert('RGB')
                # Fast downscale preserving aspect ratio
                img.thumbnail((tile_size, tile_size), resample=Image.LANCZOS)
                # Force exact square dimensions
                img = img.resize((tile_size, tile_size), resample=Image.LANCZOS)
                img.save(thumb_path)
                created += 1
        except Exception as e:
            # Don't kill the pipeline on one bad file — just log and continue
            tqdm.write(f"  skip (failed): {filename} — {e}")
            failed += 1
            continue

    print(f"\nThumbnail summary:")
    print(f"  Created new      : {created}")
    print(f"  Skipped (exists) : {skipped_existing}")
    print(f"  Failed           : {failed}")
    print(f"  Output directory : {thumb_dir}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate square thumbnails for the mosaic tile library."
    )
    parser.add_argument(
        "--source-dir", required=True,
        help="Directory containing cleaned full-size images (e.g. data/clean)."
    )
    parser.add_argument(
        "--thumb-dir", required=True,
        help="Output directory for thumbnails (e.g. data/thumbnails)."
    )
    parser.add_argument(
        "--tile-size", type=int, default=DEFAULT_TILE_SIZE,
        help=f"Tile edge length in pixels (default: {DEFAULT_TILE_SIZE})."
    )
    parser.add_argument(
        "--prefix", default="",
        help="Only process files whose names start with this string "
             "(e.g. 'face_' to thumbnail only face images from a shared clean/ dir)."
    )
    return parser.parse_args()


def main():
    args = parse_args()
    build_thumbnails(
        source_dir=args.source_dir,
        thumb_dir=args.thumb_dir,
        tile_size=args.tile_size,
        prefix=args.prefix,
    )


if __name__ == "__main__":
    main()
