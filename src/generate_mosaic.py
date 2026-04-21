"""
generate_mosaic.py
Given a target image and a pre-built LAB k-d tree, assemble a mosaic
by replacing each cell of the target with the closest-matching tile.

This is stage 3 of the pipeline. It depends on the pickle produced
by build_database.py but is otherwise independent — you can generate
many different mosaics from one database without rebuilding.

Parallel tile loading:
    The bottleneck in mosaic assembly is opening and resizing thousands
    of tile images from disk. This script uses Python's multiprocessing
    module to distribute tile loading across multiple CPU cores. On
    SLURM, the worker count automatically matches --cpus-per-task;
    locally it falls back to the machine's core count.

    The "initializer" pattern is used instead of passing the filenames
    list inside every task tuple. Without it, the full list (50,000+
    strings) would be pickled and sent over IPC once per task — for a
    200x200 grid that's 40,000 redundant copies. The initializer runs
    once per worker process and sets the list into module-level globals,
    so each task only needs to send its (index, tile_index) pair.

    Reference: https://docs.python.org/3/library/multiprocessing.html#module-multiprocessing.pool

Usage:
    python src/generate_mosaic.py \\
        --pkl-path data/color_tree.pkl \\
        --target data/target/dwayne_johnson.webp \\
        --output output/mosaic.jpg \\
        --grid-size 100 \\
        --tile-size 32
"""

import argparse
import multiprocessing as mp
import os
import pickle
import sys

import numpy as np
from PIL import Image
from skimage import color
from tqdm import tqdm

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import DEFAULT_TILE_SIZE, DEFAULT_GRID_SIZE


# ---------------------------------------------------------------------------
# Module-level globals for multiprocessing workers — NOT taught in class
#
# These variables are set once per worker process by _init_worker().
# They must be module-level (not inside a function) because each worker
# is a forked copy of the main process, and multiprocessing.Pool's
# initializer sets up the worker's global scope before any tasks run.
#
# Why not just pass filenames in the task tuple?
#   Multiprocessing serializes (pickles) every argument that crosses
#   the process boundary. If filenames is a list of 50,000 strings
#   and you have 40,000 tasks, that's 40,000 copies of the same list
#   being serialized — extremely slow and memory-heavy. The initializer
#   sends it once per worker (e.g. 32 copies for 32 cores) instead.
#
# This pattern is standard for any Python multiprocessing workload
# where tasks share large read-only data. You'd use the same approach
# for a shared lookup table, a pre-loaded ML model, or a database
# connection pool.
#
# Reference: https://docs.python.org/3/library/multiprocessing.html#multiprocessing.pool.Pool
# ---------------------------------------------------------------------------
_worker_filenames = None
_worker_tile_size = None


def _init_worker(filenames, tile_size):
    """
    Called once per worker process when the Pool starts up.
    Sets shared read-only data into the worker's global scope so
    that load_tile() can access it without receiving it per-task.
    """
    global _worker_filenames, _worker_tile_size
    _worker_filenames = filenames
    _worker_tile_size = tile_size


def _load_tile(args):
    """
    Load one tile from disk and return its pixel data as a numpy array.

    Args:
        args: tuple of (cell_index, tile_index)
              cell_index  — position in the flattened grid (for reassembly)
              tile_index  — index into the filenames list (from KDTree.query)

    Returns:
        (cell_index, numpy_array) on success, or (cell_index, None) on failure.

    Why return a numpy array instead of a PIL Image?
        PIL Images are not picklable across process boundaries in all
        configurations. Numpy arrays serialize cleanly and we convert
        back to PIL only during the paste step in the main process.
    """
    i, idx = args
    try:
        with Image.open(_worker_filenames[idx]) as tile:
            tile = tile.convert('RGB').resize(
                (_worker_tile_size, _worker_tile_size),
                resample=Image.LANCZOS
            )
            return i, np.array(tile)
    except Exception:
        return i, None


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
        4. Load matched tiles in parallel across available CPU cores.
        5. Paste each tile onto the output canvas.
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
    # 4. Load tiles in parallel — NOT taught in class
    #
    # SLURM_CPUS_PER_TASK is set automatically by SLURM when you
    # request --cpus-per-task=N. Reading it here means the Python
    # code matches whatever the .slurm file requests — no need to
    # keep two numbers in sync manually.
    #
    # mp.cpu_count() is the fallback for local (non-SLURM) runs.
    #
    # imap() streams results back one at a time (unlike map() which
    # waits for all tasks to finish). This lets the tqdm progress bar
    # update in real time. chunksize=64 groups tasks into batches sent
    # to workers together, reducing the per-task IPC overhead.
    #
    # Reference: https://docs.python.org/3/library/multiprocessing.html
    # Reference: https://docs.python.org/3/library/os.html#os.environ
    # ------------------------------------------------------------------
    num_workers = int(os.environ.get("SLURM_CPUS_PER_TASK", mp.cpu_count()))
    print(f"Loading tiles in parallel with {num_workers} workers...")

    # Each task is just (cell_index, tile_index) — the filenames list
    # is shared via _init_worker, not copied per task.
    tasks = [(i, int(idx)) for i, idx in enumerate(indices)]

    with mp.Pool(
        processes=num_workers,
        initializer=_init_worker,
        initargs=(filenames, tile_size)
    ) as pool:
        results = list(tqdm(
            pool.imap(_load_tile, tasks, chunksize=64),
            total=len(tasks),
            desc="Loading tiles"
        ))

    # ------------------------------------------------------------------
    # 5. Assemble the canvas
    # ------------------------------------------------------------------
    canvas_w = grid_w * tile_size
    canvas_h = grid_h * tile_size
    print(f"Building {canvas_w}x{canvas_h} canvas...")
    canvas = Image.new('RGB', (canvas_w, canvas_h))

    failed_tiles = 0
    for i, tile_array in results:
        if tile_array is None:
            failed_tiles += 1
            continue
        x = (i % grid_w) * tile_size
        y = (i // grid_w) * tile_size
        canvas.paste(Image.fromarray(tile_array), (x, y))

    # Ensure output directory exists, then save
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    print(f"Saving mosaic to {output_path}...")
    canvas.save(output_path, quality=95)

    print(f"\nMosaic summary:")
    print(f"  Grid cells   : {grid_w} x {grid_h} = {grid_w * grid_h}")
    print(f"  Tile size    : {tile_size}x{tile_size}")
    print(f"  Canvas size  : {canvas_w}x{canvas_h}")
    print(f"  Workers used : {num_workers}")
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
