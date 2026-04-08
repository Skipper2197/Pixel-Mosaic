import os
import subprocess
import pickle
import numpy as np
from scipy.spatial import KDTree
from tqdm import tqdm

# --- CONFIGURATION (SciClone Paths) ---
BASE_DIR = '/sciclone/scr10/gzdata440/Pixel-Mosaic'
SOURCE_DIR = os.path.join(BASE_DIR, 'data/1m_faces_55')
THUMB_DIR = os.path.join(BASE_DIR, 'data/thumbnails')
TARGET_IMAGE = os.path.join(BASE_DIR, 'data/dwayne-johnson-walk-of-fame-honor.webp')
OUTPUT_IMAGE = os.path.join(BASE_DIR, 'test.jpg')
PKL_PATH = os.path.join(BASE_DIR, 'color_tree.pkl')

GRID_SIZE = (100, 100)  # 100x100 grid
TILE_DIM = "32x32"      # Square tiles

def ensure_thumbnails():
    """Generates 32x32 thumbnails in bulk using ImageMagick mogrify."""
    if not os.path.exists(THUMB_DIR):
        print(f"Creating thumbnail directory: {THUMB_DIR}")
        os.makedirs(THUMB_DIR, exist_ok=True)
    
    # Check if directory is empty
    if not os.listdir(THUMB_DIR):
        print("Generating 32x32 thumbnails... this may take a few minutes.")
        # We use mogrify with a wildcard to process the source directory
        # The asterisk must be handled carefully in subprocess
        cmd = (
            f"magick mogrify -path {THUMB_DIR} "
            f"-thumbnail {TILE_DIM}^ -gravity center -extent {TILE_DIM} "
            f"-format jpg {os.path.join(SOURCE_DIR, '*')}"
        )
        # Using shell=True here to allow the shell to expand the '*' wildcard
        subprocess.run(cmd, shell=True, check=True)
        print(f"Thumbnails generated in {THUMB_DIR}")
    else:
        print("Thumbnails already exist. Skipping generation.")

def get_avg_lab_magick(img_path):
    """Extracts average LAB color using a 1x1 resize."""
    cmd = [
        "magick", img_path,
        "-resize", "1x1!",
        "-colorspace", "Lab",
        "-format", "%[fx:u.p{0,0}.r*100] %[fx:u.p{0,0}.g*255-128] %[fx:u.p{0,0}.b*255-128]",
        "info:"
    ]
    try:
        result = subprocess.check_output(cmd).decode('utf-8').split()
        return [float(x) for x in result]
    except Exception:
        return None

def build_library():
    """Indexes thumbnails and saves to a KDTree pickle."""
    if os.path.exists(PKL_PATH):
        print(f"Loading existing library from {PKL_PATH}...")
        with open(PKL_PATH, 'rb') as f:
            return pickle.load(f)

    filenames = []
    lab_values = []
    
    # Get all jpg files in THUMB_DIR
    all_files = [os.path.join(THUMB_DIR, f) for f in os.listdir(THUMB_DIR) if f.endswith('.jpg')]
    
    print(f"Indexing {len(all_files)} images...")
    for path in tqdm(all_files, desc='Building Color Tree'):
        lab = get_avg_lab_magick(path)
        if lab:
            lab_values.append(lab)
            filenames.append(path)

    data = {'tree': KDTree(np.array(lab_values)), 'filenames': filenames}
    with open(PKL_PATH, 'wb') as f:
        pickle.dump(data, f)
    return data

def generate_mosaic(data, target_path, output_name, grid):
    tree, filenames = data['tree'], data['filenames']
    

    # This resizes to the grid and outputs every pixel as a line of text
    cmd = [
        "magick", target_path,
        "-resize", f"{grid[0]}x{grid[1]}!",
        "-colorspace", "Lab",
        "-format", "%[fx:u*100] %[fx:v*255-128] %[fx:w*255-128]\n", 
        "txt:" # Use the txt: delegate to stream all pixels
    ]
    # We skip the first line because it's header info from the 'txt:' format
    raw_output = subprocess.check_output(cmd).decode('utf-8').splitlines()[1:]
    
    target_lab = []
    for line in raw_output:
        # Extract just the color values from the ImageMagick txt output
        # Example line: 0,0: (25.1, -2, 14) #ABCDEF lab(25.1%, -2, 14)
        if '(' in line:
            parts = line.split('(')[1].split(')')[0].replace(',', ' ').split()
            target_lab.append([float(x) for x in parts[:3]])

    print(f"Target color list length: {len(target_lab)}") 
    # This SHOULD be 10000 (100x100)

    print("Matching tiles...")
    _, indices = tree.query(target_lab)
    
    list_file = "match_list.txt"
    with open(list_file, "w") as f:
        for idx in indices:
            f.write(f'"{filenames[idx]}"\n')

    print("Assembling final mosaic...")
    # montage command with resource limits and font fixes
    subprocess.run([
        "magick", "montage",
        "-limit", "memory", "16GiB",
        "-limit", "map", "32GiB",
        "-font", "Courier", "-pointsize", "0",
        f"@{list_file}",
        "-tile", f"{grid[0]}x{grid[1]}",
        "-geometry", f"{TILE_DIM}+0+0",
        output_name
    ])
    if os.path.exists(list_file): os.remove(list_file)

def main():
    ensure_thumbnails()
    data = build_library()
    generate_mosaic(data, TARGET_IMAGE, OUTPUT_IMAGE, GRID_SIZE)
    print(f"Success! Mosaic saved as {OUTPUT_IMAGE}")

if __name__ == '__main__':
    main()
