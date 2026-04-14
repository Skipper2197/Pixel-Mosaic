"""
build_database.py
Read every thumbnail in a directory, compute its average LAB color,
and store the results in a k-d tree pickled to disk.

This is stage 2 of the database build. It depends on the output of
build_thumbnails.py but has no knowledge of where those thumbnails
came from — any directory of square images will work.

Usage:
    python src/build_database.py \\
        --thumb-dir data/thumbnails \\
        --pkl-path data/color_tree.pkl

Why a k-d tree instead of brute-force search?
    At mosaic-generation time we do one nearest-neighbor lookup per
    target cell. For a 100x100 grid that's 10,000 lookups, and each
    lookup against ~50,000 thumbnails brute-force would be 500M
    distance computations. A k-d tree reduces this to roughly
    O(10,000 * log 50,000) ~ 160,000 comparisons. See README.md.

Idempotency:
    If the pickle already exists at --pkl-path, the script exits
    successfully without rebuilding. Delete the pickle to force a
    rebuild (e.g., after tweaking the LAB function in common.py).
"""

import argparse
import os
import pickle
import sys

import numpy as np
from scipy.spatial import KDTree
from tqdm import tqdm

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import get_avg_lab_centered, list_images


def build_database(thumb_dir, pkl_path, force=False):
    """
    Build a k-d tree over the average LAB colors of every thumbnail
    in thumb_dir and pickle it to pkl_path.

    The pickled object is a dict with two keys:
        'tree'      : scipy.spatial.KDTree indexed by LAB position
        'filenames' : list[str] of absolute paths, parallel to the
                      tree's data array — tree index i corresponds
                      to filenames[i].

    Why pickle and not JSON/CSV?
        The KDTree object is a compiled C structure with no natural
        text representation. Pickle preserves it directly. The
        downside — pickle is Python-specific — is fine here because
        both writer and reader are Python scripts in the same repo.
    """
    # Idempotency check — skip if already built
    if os.path.exists(pkl_path) and not force:
        print(f"Database already exists at {pkl_path}")
        print(f"(delete the file or pass --force to rebuild)")
        return

    if not os.path.isdir(thumb_dir):
        raise FileNotFoundError(f"Thumbnail directory not found: {thumb_dir}")

    # Ensure parent directory for pkl_path exists
    os.makedirs(os.path.dirname(pkl_path) or ".", exist_ok=True)

    thumb_files = list_images(thumb_dir)
    if not thumb_files:
        raise ValueError(f"No thumbnails found in {thumb_dir}")

    print(f"Indexing {len(thumb_files)} thumbnails in LAB space...")

    # We accumulate two parallel lists and then convert to arrays.
    # Appending to lists is O(1) amortized; building a numpy array
    # incrementally would be O(n^2) due to repeated reallocation.
    filenames = []
    lab_values = []
    failed = 0

    for filename in tqdm(thumb_files, desc="Building LAB tree"):
        path = os.path.join(thumb_dir, filename)
        lab = get_avg_lab_centered(path)

        if lab is not None:
            lab_values.append(lab)
            # Store absolute path so generate_mosaic.py can open the
            # tile regardless of its working directory
            filenames.append(os.path.abspath(path))
        else:
            failed += 1

    if not lab_values:
        raise RuntimeError("No valid LAB values computed — all images failed.")

    lab_array = np.array(lab_values)

    print(f"Constructing k-d tree from {len(lab_array)} points...")
    tree = KDTree(lab_array)

    data = {'tree': tree, 'filenames': filenames}

    print(f"Pickling database to {pkl_path}...")
    with open(pkl_path, 'wb') as f:
        pickle.dump(data, f)

    print(f"\nDatabase summary:")
    print(f"  Indexed tiles : {len(filenames)}")
    print(f"  Failed tiles  : {failed}")
    print(f"  Pickle size   : {os.path.getsize(pkl_path):,} bytes")
    print(f"  Output        : {pkl_path}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build a LAB-color k-d tree over a directory of thumbnails."
    )
    parser.add_argument(
        "--thumb-dir", required=True,
        help="Directory of square thumbnail images (output of build_thumbnails.py)."
    )
    parser.add_argument(
        "--pkl-path", required=True,
        help="Output path for the pickled k-d tree (e.g. data/color_tree.pkl)."
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Rebuild even if --pkl-path already exists."
    )
    return parser.parse_args()


def main():
    args = parse_args()
    build_database(
        thumb_dir=args.thumb_dir,
        pkl_path=args.pkl_path,
        force=args.force,
    )


if __name__ == "__main__":
    main()
