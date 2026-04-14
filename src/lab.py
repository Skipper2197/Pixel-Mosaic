import os
import pickle
import numpy as np
from PIL import Image
from scipy.spatial import KDTree
from tqdm import tqdm
from skimage import color  # Efficient LAB conversion

# --- CONFIGURATION ---
SHARED_DIR = '/sciclone/scr10/gzdata440/Pixel-Mosaic/data'

SOURCE_DIR = f'{SHARED_DIR}/raw/flowers'
THUMB_DIR = f'{SHARED_DIR}/thumbnails/flowers'
TARGET_IMAGE = f'{SHARED_DIR}/dwayne-johnson-walk-of-fame-honor.webp'
# TARGET_IMAGE = './data/target/dwayne_johnson.jpg'

OUTPUT_IMAGE = './output/mosaic_lab_slurm_flowers.jpg'
PKL_PATH = './color_trees/color_tree_flowers.pkl'  # Updated name to avoid loading old RGB data

GRID_SIZE = (200, 200)
TILE_SIZE = 32

# -------- ROCK DATASET ---------------- #
# SOURCE_DIR = './data/rock_data'     # Where your original high-res rock photos are
# THUMB_DIR = './data/rock_thumbnails'     # Where the 32x32 tiles will be stored
# TARGET_IMAGE = './data/dwayne_johnson.webp'
# OUTPUT_IMAGE = './rockception_2.jpg'
# PKL_PATH = './rock_library_lab_2_2.pkl'

# GRID_SIZE = (200, 200)  # High resolution for "The Rock"
# TILE_SIZE = 32          # Standard tile size

def get_avg_lab_centered(path):
    """
    Opens an image, crops to the center, gets average RGB,
    and converts it to LAB for the library.
    """
    try:
        with Image.open(path) as img:
            img = img.convert('RGB')
            w, h = img.size
            
            # Center crop (50% area)
            left, top, right, bottom = w * 0.25, h * 0.25, w * 0.75, h * 0.75
            img = img.crop((left, top, right, bottom))
            
            # Get average RGB
            avg_img = img.resize((1, 1), resample=Image.LANCZOS)
            avg_rgb = np.array(avg_img.getpixel((0, 0))) / 255.0  # Normalize to 0-1 for skimage
            
            # Convert single pixel to LAB
            # skimage expects (Height, Width, Channel) format
            lab_pixel = color.rgb2lab(avg_rgb.reshape(1, 1, 3))
            return lab_pixel.flatten()
    except Exception:
        return None
    
def get_avg_lab_full(path):
    """Gets LAB color for the whole tile (since rocks are textures)."""
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
    """Generates physical thumbnails to save RAM and time during mosaic creation."""
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
                    # Use thumbnail() to maintain aspect ratio, then crop/resize to square
                    img.thumbnail((TILE_SIZE, TILE_SIZE), resample=Image.LANCZOS)
                    # Force exact tile dimensions
                    img = img.resize((TILE_SIZE, TILE_SIZE), resample=Image.LANCZOS)
                    img.save(thumb_path)
            except Exception:
                continue

def build_library():
    """Reads source images and stores avg LAB color in a KDTree."""
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

def generate_mosaic(data, target_path):
    tree, filenames = data['tree'], data['filenames']

    # 1. Prepare Target Image
    print("Analyzing target image in LAB space...")
    with Image.open(target_path) as target:
        target = target.convert('RGB')
        target_small = target.resize(GRID_SIZE, resample=Image.LANCZOS)
        
        # Convert the entire target grid to LAB at once
        target_rgb_array = np.array(target_small) / 255.0
        target_lab_array = color.rgb2lab(target_rgb_array)
        
        # Flatten to 10,000 pixels with 3 channels (L, a, b)
        target_pixels_lab = target_lab_array.reshape(-1, 3)

    # 2. Find closest matches using perceptual distance
    print("Finding best matches (LAB Euclidean distance)...")
    _, indices = tree.query(target_pixels_lab)

    # 3. Assemble the Canvas
    print("Building final mosaic canvas...")
    canvas_w = GRID_SIZE[0] * TILE_SIZE
    canvas_h = GRID_SIZE[1] * TILE_SIZE
    canvas = Image.new('RGB', (canvas_w, canvas_h))

    for i, idx in enumerate(tqdm(indices, desc="Placing Tiles")):
        x = (i % GRID_SIZE[0]) * TILE_SIZE
        y = (i // GRID_SIZE[0]) * TILE_SIZE
        
        try:
            with Image.open(filenames[idx]) as tile:
                tile = tile.convert('RGB').resize((TILE_SIZE, TILE_SIZE), resample=Image.LANCZOS)
                canvas.paste(tile, (x, y))
        except:
            continue

    print(f"Saving final LAB result to {OUTPUT_IMAGE}...")
    canvas.save(OUTPUT_IMAGE, quality=95)

def main():
    if not os.path.exists(SOURCE_DIR):
        print(f"Error: {SOURCE_DIR} not found.")
        return
    
    # 1. Ensure small tile images exist on disk
    pre_process_thumbnails()
    
    # 2. Build the color tree using the thumbnails
    data = build_library()
    
    # 3. Create the Rock-themed Rock mosaic
    generate_mosaic(data, TARGET_IMAGE)

if __name__ == '__main__':
    main()
