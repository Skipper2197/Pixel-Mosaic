import os 
import subprocess
import numpy as np
from scipy.spatial import KDTree
from skimage import color
import pickle
from tqdm import tqdm

BASE_DIR = '/sciclone/scr10/gzdata440/Pixel-Mosaic'
IMAGE_DIR = os.path.join(BASE_DIR, 'data/1m_faces_55')
TARGET_IMAGE = os.path.join(BASE_DIR, 'data/dwayne-johnson-walk-of-fame-honor.webp')
OUTPUT_IMAGE = os.path.join(BASE_DIR, 'test.jpg')
PKL_PATH = os.path.join(BASE_DIR, 'color_tree.pkl')
THUMB_DIR = os.path.join(BASE_DIR, 'data/thumbnails')

GRID_SIZE = (100, 100) # 100x100 grid
TILE_DIM = "32x32"

def get_avg_lab_magick(img_path):
    # Standardize path to handle spaces or relative path issues
    full_path = os.path.abspath(img_path)
    
    cmd = [
        "magick", full_path, 
        "-resize", "1x1!", 
        "-colorspace", "Lab", 
        # Using .r, .g, .b to represent L, a, b channels respectively
        "-format", "%[fx:u.p{0,0}.r*100] %[fx:u.p{0,0}.g*255-128] %[fx:u.p{0,0}.b*255-128]", 
        "info:"
    ]
    
    try:
        result = subprocess.check_output(cmd).decode('utf-8').split()
        return [float(x) for x in result]
    except subprocess.CalledProcessError as e:
        print(f"Error processing {img_path}: {e}")
        return None
    
def build_and_save_library(source_dir, pkl_output):
    """Scans directory, builds KD-Tree, and pickles the result."""
    filenames = []
    lab_values = []

    all_files = [f for f in os.listdir(source_dir)]
    
    print(f"Indexing images from {source_dir}...")
    for img_name in tqdm(all_files, desc='Processing Images to Tree', unit='img', mininterval=10):
        path = os.path.join(source_dir, img_name)
        lab = get_avg_lab_magick(path)
        
        if lab:
            lab_values.append(lab)
            filenames.append(path)

    tree = KDTree(np.array(lab_values))
    
    with open(pkl_output, 'wb') as f:
        pickle.dump({'tree': tree, 'filenames': filenames}, f)
    print(f"Library saved to {pkl_output}")

def generate_mosaic(target_path, pkl_path, output_name, grid_size):
    print("Loading library (this may take a moment)...")
    with open(pkl_path, 'rb') as f:
        data = pickle.load(f)
        tree = data['tree']
        filenames = data['filenames']

    print("Extracting colors from target...")
    # Get raw Lab values without the 'txt:' overhead
    # This format is much easier for Python to parse without huge string lists
    cmd = [
        "magick", target_path, 
        "-resize", f"{grid_size[0]}x{grid_size[1]}!", 
        "-colorspace", "Lab", 
        "-format", "%[fx:u.p{0,0}.r*100] %[fx:u.p{0,0}.g*255-128] %[fx:u.p{0,0}.b*255-128]\n", 
        "info:"
    ]
    
    # We use a generator/iterator to save memory
    raw_output = subprocess.check_output(cmd).decode('utf-8').splitlines()
    target_lab = [list(map(float, line.split())) for line in raw_output if line.strip()]

    print(f"Querying KD-Tree for {len(target_lab)} matches...")
    # Use a small 'leafsize' or workers if your HPC node has many cores
    _, indices = tree.query(target_lab, workers=4)
    
    list_file = "match_list.txt"
    print(f"Writing {list_file}...")
    with open(list_file, "w") as f:
        for idx in indices:
            # Use a relative path or absolute path - absolute is safer on SciClone
            f.write(f'"{os.path.abspath(filenames[idx])}"\n')
    
    # Verify the file exists before moving to montage
    if os.path.exists(list_file):
        print(f"Successfully created {list_file} ({os.path.getsize(list_file)} bytes)")
    else:
        raise FileNotFoundError("Failed to create match_list.txt")

    print("Starting montage assembly...")
    # Pass the memory limits directly into the subprocess call
    subprocess.run([
        "magick", "montage", 
        "-limit", "memory", "16GiB", 
        "-limit", "map", "32GiB",
        f"@{list_file}",
        "-tile", f"{grid_size[0]}x{grid_size[1]}",
        "-geometry", "32x32+0+0", 
        output_name
    ])

def main():
    if not os.path.exists(PKL_PATH):
        build_and_save_library(IMAGE_DIR, PKL_PATH) # Total Time = ~3 mins
    
    generate_mosaic(TARGET_IMAGE, PKL_PATH, OUTPUT_IMAGE, GRID_SIZE)

if __name__ == '__main__':
    main()
