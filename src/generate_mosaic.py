"""
generate_mosaic.py
Given a target image and a pre-built LAB k-d tree, assemble a mosaic
by replacing each cell of the target with the closest-matching tile.

This is stage 3 of the pipeline. It depends on the pickle produced
by build_database.py but is otherwise independent — you can generate
many different mosaics from one database without rebuilding.

Usage:
    python src/generate_mosaic.py \\
        --pkl-path data/color_tree.pkl \\
        --target data/target/dwayne_johnson.webp \\
        --output output/mosaic.jpg \\
        --grid-size 100 \\
        --tile-size 32
"""

import argparse
import os
import pickle
import sys

import numpy as np
from PIL import Image
from skimage import color
from tqdm import tqdm

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import DEFAULT_TILE_SIZE, DEFAULT_GRID_SIZE


def load_database(pkl_path):
    """Load the pickled dict produced by build_database.py."""
    if not os.path.exists(pkl_path):
        raise FileNotFoundError(
            f"Database not found: {pkl_path}\n"
            f"Run 02b_build_database.sh first."
        )
    with open(pkl_path, 'rb') as f:
        return pickle.load(f)


def generate_mosaic(data, target_path, output_path, grid_size, tile_size):
    """
    Build the mosaic canvas.

    Algorithm:
        1. Downsample the target to (grid_size x grid_size) cells.
        2. Convert the entire downsampled image to LAB at once
           (vectorized — much faster than per-pixel conversion).
        3. Query the k-d tree for the nearest tile to each cell.
        4. Paste each matched tile onto the output canvas.
    """
    tree = data['tree']
    filenames = data['filenames']

    grid_w, grid_h = grid_size

    # ------------------------------------------------------------------
    # 1-2. Prepare target in LAB space
    # ------------------------------------------------------------------
    print(f"Analyzing target image: {target_path}")
    with Image.open(target_path) as target:
        target = target.convert('RGB')
        target_small = target.resize((grid_w, grid_h), resample=Image.LANCZOS)

        # Convert entire grid to LAB in one call — vastly faster than
        # looping. skimage.color.rgb2lab is vectorized over arbitrary
        # array shapes as long as the last axis is RGB.
        target_rgb_array = np.array(target_small) / 255.0
        target_lab_array = color.rgb2lab(target_rgb_array)

        # Flatten to (N, 3) so KDTree.query can handle all cells at once
        target_pixels_lab = target_lab_array.reshape(-1, 3)

    # ------------------------------------------------------------------
    # 3. Nearest-neighbor lookup — one batched call, not a loop
    # ------------------------------------------------------------------
    print(f"Querying k-d tree for {len(target_pixels_lab)} cells...")
    _, indices = tree.query(target_pixels_lab)

    # ------------------------------------------------------------------
    # 4. Assemble the canvas
    # ------------------------------------------------------------------
    canvas_w = grid_w * tile_size
    canvas_h = grid_h * tile_size
    print(f"Building {canvas_w}x{canvas_h} canvas...")
    canvas = Image.new('RGB', (canvas_w, canvas_h))

    failed_tiles = 0
    for i, idx in enumerate(tqdm(indices, desc="Placing tiles")):
        x = (i % grid_w) * tile_size
        y = (i // grid_w) * tile_size

        try:
            with Image.open(filenames[idx]) as tile:
                tile = tile.convert('RGB').resize(
                    (tile_size, tile_size), resample=Image.LANCZOS
                )
                canvas.paste(tile, (x, y))
        except Exception:
            failed_tiles += 1
            continue

    # Ensure output directory exists, then save
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    print(f"Saving mosaic to {output_path}...")
    canvas.save(output_path, quality=95)

    print(f"\nMosaic summary:")
    print(f"  Grid cells   : {grid_w} x {grid_h} = {grid_w * grid_h}")
    print(f"  Tile size    : {tile_size}x{tile_size}")
    print(f"  Canvas size  : {canvas_w}x{canvas_h}")
    print(f"  Failed tiles : {failed_tiles}")
    print(f"  Output       : {output_path}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate a photomosaic from a pre-built LAB k-d tree."
    )
    parser.add_argument(
        "--pkl-path", required=True,
        help="Path to the pickled database (output of build_database.py)."
    )
    parser.add_argument(
        "--target", required=True,
        help="Target image to reproduce as a mosaic."
    )
    parser.add_argument(
        "--output", required=True,
        help="Output path for the generated mosaic JPEG."
    )
    parser.add_argument(
        "--grid-size", type=int, default=DEFAULT_GRID_SIZE[0],
        help=f"Number of cells per side (default: {DEFAULT_GRID_SIZE[0]})."
    )
    parser.add_argument(
        "--tile-size", type=int, default=DEFAULT_TILE_SIZE,
        help=f"Tile edge length in pixels (default: {DEFAULT_TILE_SIZE})."
    )
    return parser.parse_args()


def main():
    args = parse_args()
    data = load_database(args.pkl_path)
    generate_mosaic(
        data=data,
        target_path=args.target,
        output_path=args.output,
        grid_size=(args.grid_size, args.grid_size),
        tile_size=args.tile_size,
    )


if __name__ == "__main__":
    main()
