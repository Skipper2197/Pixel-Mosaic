import os
import pickle
import numpy as np
from PIL import Image
from scipy.spatial import KDTree
from tqdm import tqdm

# --- CONFIGURATION ---
SOURCE_DIR = './data/raw/1m_faces_55'   # Folder containing your 1m_faces
TARGET_IMAGE = './data/target/dwayne-johnson-walk-of-fame-honor.webp'    # The image you want to recreate
OUTPUT_IMAGE = './output/mosaic_rgb.jpg'
PKL_PATH = './color_trees/color_tree_rgb_avg.pkl'

GRID_SIZE = (200, 200)  # Number of tiles (Width, Height)
TILE_SIZE = 32          # Resolution of each tile (32x32 pixels)

def get_avg_rgb_centered(path):
    """
    Opens an image, crops to the center 50% to focus on the face,
    and returns the average RGB color.
    """
    try:
        with Image.open(path) as img:
            img = img.convert('RGB')
            w, h = img.size
            
            # Define a central box (50% of width and height) 
            # to avoid background/shirt colors
            left = w * 0.25
            top = h * 0.25
            right = w * 0.75
            bottom = h * 0.75
            
            img = img.crop((left, top, right, bottom))
            
            # Reduce to 1x1 to get the mathematical average
            avg_img = img.resize((1, 1), resample=Image.LANCZOS)
            return np.array(avg_img.getpixel((0, 0)))
    except Exception:
        return None

def build_library():
    """Reads source images and stores avg color in a KDTree."""
    if os.path.exists(PKL_PATH):
        print(f"Loading existing library from {PKL_PATH}...")
        with open(PKL_PATH, 'rb') as f:
            return pickle.load(f)

    filenames, colors = [], []
    extensions = ('.jpg', '.jpeg', '.png', '.webp')
    
    # Filter for valid image files
    all_files = [os.path.join(SOURCE_DIR, f) for f in os.listdir(SOURCE_DIR) 
                 if f.lower().endswith(extensions)]
    
    if not all_files:
        raise ValueError(f"No images found in {SOURCE_DIR}")

    print(f"Indexing {len(all_files)} images with center-cropping...")
    for path in tqdm(all_files, desc="Building Color Library"):
        rgb = get_avg_rgb_centered(path)
        if rgb is not None:
            colors.append(rgb)
            filenames.append(path)

    data = {'tree': KDTree(np.array(colors)), 'filenames': filenames}
    
    with open(PKL_PATH, 'wb') as f:
        pickle.dump(data, f)
    return data

def generate_mosaic(data, target_path):
    tree, filenames = data['tree'], data['filenames']

    # 1. Prepare Target Image
    print("Analyzing target image...")
    with Image.open(target_path) as target:
        target = target.convert('RGB')
        # Resize target to the grid size (e.g., 100x100)
        target_small = target.resize(GRID_SIZE, resample=Image.LANCZOS)
        target_pixels = np.array(target_small).reshape(-1, 3)

    # 2. Find closest matches
    print("Finding best matches for each tile...")
    _, indices = tree.query(target_pixels)

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
            # If a specific tile fails to load during assembly, skip it
            continue

    print(f"Saving final result to {OUTPUT_IMAGE}...")
    canvas.save(OUTPUT_IMAGE, quality=95)

def main():
    if not os.path.exists(SOURCE_DIR):
        print(f"Error: Directory '{SOURCE_DIR}' not found. Please check your paths.")
        return
    
    # 1. Rebuild or load the library
    data = build_library()
    
    # 2. Generate the mosaic
    generate_mosaic(data, TARGET_IMAGE)
    print("\nDone! Check your output image.")

if __name__ == '__main__':
    main()
