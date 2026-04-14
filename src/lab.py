import os
import pickle
import numpy as np
from PIL import Image
from scipy.spatial import KDTree
from tqdm import tqdm
from skimage import color
import multiprocessing as mp

# --- CONFIGURATION ---
SHARED_DIR = '/sciclone/scr10/gzdata440/Pixel-Mosaic/data'
SOURCE_DIR = f'{SHARED_DIR}/raw/1m_faces_55'
THUMB_DIR = f'{SHARED_DIR}/thumbnails/face_thumbnails'
TARGET_IMAGE = f'{SHARED_DIR}/dwayne-johnson-walk-of-fame-honor.webp'
OUTPUT_IMAGE = './output/mosaic_lab_slurm.jpg'
PKL_PATH = './color_trees/color_tree_lab_avg_2.pkl'

GRID_SIZE = (200, 200)
TILE_SIZE = 32


def get_avg_lab_centered(path):
    try:
        with Image.open(path) as img:
            img = img.convert('RGB')
            w, h = img.size
            left, top, right, bottom = w * 0.25, h * 0.25, w * 0.75, h * 0.75
            img = img.crop((left, top, right, bottom))
            avg_img = img.resize((1, 1), resample=Image.LANCZOS)
            avg_rgb = np.array(avg_img.getpixel((0, 0))) / 255.0
            lab_pixel = color.rgb2lab(avg_rgb.reshape(1, 1, 3))
            return lab_pixel.flatten()
    except Exception:
        return None


def get_avg_lab_full(path):
    try:
        with Image.open(path) as img:
            img = img.convert('RGB')
            avg_img = img.resize((1, 1), resample=Image.LANCZOS)
            avg_rgb = np.array(avg_img.getpixel((0, 0))) / 255.0
            lab_pixel = color.rgb2lab(avg_rgb.reshape(1, 1, 3))
            return lab_pixel.flatten()
    except Exception:
        return None


def pre_process_thumbnails():
    if not os.path.exists(THUMB_DIR):
        os.makedirs(THUMB_DIR)
    extensions = ('.jpg', '.jpeg', '.png', '.webp')
    raw_files = [f for f in os.listdir(SOURCE_DIR) if f.lower().endswith(extensions)]
    print(f"Checking/Creating thumbnails for {len(raw_files)} images...")
    for f in tqdm(raw_files, desc="Processing Tiles"):
        source_path = os.path.join(SOURCE_DIR, f)
        thumb_path = os.path.join(THUMB_DIR, f)
        if not os.path.exists(thumb_path):
            try:
                with Image.open(source_path) as img:
                    img = img.convert('RGB')
                    img.thumbnail((TILE_SIZE, TILE_SIZE), resample=Image.LANCZOS)
                    img = img.resize((TILE_SIZE, TILE_SIZE), resample=Image.LANCZOS)
                    img.save(thumb_path)
            except Exception:
                continue


def build_library():
    if os.path.exists(PKL_PATH):
        print(f"Loading existing LAB library from {PKL_PATH}...")
        with open(PKL_PATH, 'rb') as f:
            return pickle.load(f)

    filenames, lab_values = [], []
    extensions = ('.jpg', '.jpeg', '.png', '.webp')
    all_files = [os.path.join(SOURCE_DIR, f) for f in os.listdir(SOURCE_DIR)
                 if f.lower().endswith(extensions)]
    if not all_files:
        raise ValueError(f"No images found in {SOURCE_DIR}")

    print(f"Indexing {len(all_files)} images in LAB space...")
    for path in tqdm(all_files, desc="Building LAB Tree"):
        lab = get_avg_lab_centered(path)
        if lab is not None:
            lab_values.append(lab)
            filenames.append(path)

    data = {'tree': KDTree(np.array(lab_values)), 'filenames': filenames}
    with open(PKL_PATH, 'wb') as f:
        pickle.dump(data, f)
    return data


def load_tile(args):
    """Load one tile from disk and return its pixel data as a numpy array."""
    i, idx, filenames = args
    try:
        with Image.open(filenames[idx]) as tile:
            tile = tile.convert('RGB').resize((TILE_SIZE, TILE_SIZE), resample=Image.LANCZOS)
            return i, np.array(tile)
    except Exception:
        return i, None


def generate_mosaic(data, target_path):
    tree, filenames = data['tree'], data['filenames']

    print("Analyzing target image in LAB space...")
    with Image.open(target_path) as target:
        target = target.convert('RGB')
        target_small = target.resize(GRID_SIZE, resample=Image.LANCZOS)
        target_rgb_array = np.array(target_small) / 255.0
        target_lab_array = color.rgb2lab(target_rgb_array)
        target_pixels_lab = target_lab_array.reshape(-1, 3)

    print("Finding best matches (LAB Euclidean distance)...")
    _, indices = tree.query(target_pixels_lab)

    # --- PARALLEL TILE LOADING ---
    num_workers = int(os.environ.get("SLURM_CPUS_PER_TASK", mp.cpu_count()))
    print(f"Loading tiles in parallel with {num_workers} workers...")

    tasks = [(i, int(idx), filenames) for i, idx in enumerate(indices)]

    with mp.Pool(processes=num_workers) as pool:
        results = list(tqdm(pool.imap(load_tile, tasks, chunksize=64), 
                            total=len(tasks), desc="Loading Tiles"))

    print("Assembling canvas...")
    canvas_w = GRID_SIZE[0] * TILE_SIZE
    canvas_h = GRID_SIZE[1] * TILE_SIZE
    canvas = Image.new('RGB', (canvas_w, canvas_h))

    for i, tile_array in results:
        if tile_array is None:
            continue
        x = (i % GRID_SIZE[0]) * TILE_SIZE
        y = (i // GRID_SIZE[0]) * TILE_SIZE
        canvas.paste(Image.fromarray(tile_array), (x, y))

    print(f"Saving final LAB result to {OUTPUT_IMAGE}...")
    canvas.save(OUTPUT_IMAGE, quality=95)


def main():
    if not os.path.exists(SOURCE_DIR):
        print(f"Error: {SOURCE_DIR} not found.")
        return
    pre_process_thumbnails()
    data = build_library()
    generate_mosaic(data, TARGET_IMAGE)


if __name__ == '__main__':
    main()
