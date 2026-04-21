"""
common.py
Shared utilities for the Pixel-Mosaic pipeline.

This module centralizes configuration constants and LAB colorspace helpers
so that build_thumbnails.py, build_database.py, and generate_mosaic.py do
not duplicate code or hardcoded paths. Any function or constant imported
by more than one pipeline stage belongs here.

Why a shared module?
    If get_avg_lab_centered lived in both build_database.py and
    generate_mosaic.py, a bug fix in one would silently diverge from
    the other. Centralizing ensures the same LAB math is used at
    database-build time and at mosaic-generation time, which is
    essential for the k-d tree lookups to be meaningful.
"""

import os

import numpy as np
from PIL import Image
from skimage import color  # skimage provides a vectorized rgb2lab

# ---------------------------------------------------------------------------
# Shared data directory on SciClone
#
# All pipeline stages read from and write to subdirectories under this
# path. It lives on the scratch filesystem (/sciclone/scr10) because
# the dataset is too large for home directories. The class group
# directory (gzdata440) ensures all team members can access the same
# data without duplicating multi-GB downloads.
# ---------------------------------------------------------------------------
SHARED_DIR = '/sciclone/scr10/gzdata440/Pixel-Mosaic/data'

# ---------------------------------------------------------------------------
# Default tile/grid parameters
#
# These are *defaults* — the bash wrappers can override them via CLI args.
# Hardcoding them here would break portability across datasets.
# ---------------------------------------------------------------------------
DEFAULT_TILE_SIZE = 32        # each tile is 32x32 pixels
DEFAULT_GRID_SIZE = (100, 100)  # target is sampled at 100x100 cells

# File extensions we consider "images" across the pipeline
IMAGE_EXTENSIONS = ('.jpg', '.jpeg', '.png', '.webp')


def get_avg_lab_centered(path):
    """
    Compute the average LAB color of the center 50% of an image.

    Why center-crop?
        Faces in the fake-faces dataset are framed with a lot of
        background. The center crop biases the average toward skin
        tones, which is what the mosaic should match against.

    Why LAB instead of RGB?
        Euclidean distance in LAB space approximates human perception
        of color difference — a small LAB distance looks like a small
        color change to a human eye. Euclidean distance in RGB does
        not. See README.md for the full explanation.

    Returns:
        A 3-element numpy array [L, a, b], or None if the image
        cannot be read (corrupt file, unsupported format, etc.).
    """
    try:
        with Image.open(path) as img:
            img = img.convert('RGB')
            w, h = img.size

            # Crop to the center 50% of the image (25% margin on each side)
            left, top, right, bottom = w * 0.25, h * 0.25, w * 0.75, h * 0.75
            img = img.crop((left, top, right, bottom))

            # Pillow's resize to 1x1 with LANCZOS gives a weighted
            # average of all pixels — cheaper than np.mean() on the
            # full array because it's implemented in C.
            avg_img = img.resize((1, 1), resample=Image.LANCZOS)

            # Normalize to 0-1 range because skimage's rgb2lab expects it
            avg_rgb = np.array(avg_img.getpixel((0, 0))) / 255.0

            # skimage expects (Height, Width, Channel) — reshape a
            # single pixel into a 1x1x3 "image" before conversion
            lab_pixel = color.rgb2lab(avg_rgb.reshape(1, 1, 3))
            return lab_pixel.flatten()
    except Exception:
        # Any I/O or decode error → skip this image. The caller counts
        # these as "skipped" and logs them; we don't want one corrupt
        # file to kill the whole pipeline.
        return None


def list_images(directory):
    """
    List all image files in a directory (non-recursive).

    Returns filenames, not full paths — the caller decides how to
    join them with the directory. This matches how os.listdir works
    and keeps the function composable.
    """
    return [
        f for f in os.listdir(directory)
        if f.lower().endswith(IMAGE_EXTENSIONS)
    ]
