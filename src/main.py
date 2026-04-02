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

GRID_SIZE = (100, 100) # 100x100 grid

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
    with open(pkl_path, 'rb') as f:
        data = pickle.load(f)
        tree = data['tree']
        filenames = data['filenames']

    # Map target image to grid
    cmd = [
        "magick", target_path, 
        "-resize", f"{grid_size[0]}x{grid_size[1]}!", 
        "-colorspace", "Lab", 
        "txt:"
    ]
    
    raw_pixels = subprocess.check_output(cmd).decode('utf-8').splitlines()
    
    # Extract image LAB values
    target_lab = []
    for line in raw_pixels[1:]: # Skip header
        try:
            val = line.split('lab(')[1].split(')')[0]
            l, a, b = val.split(',')
            target_lab.append([float(l.replace('%','')), float(a), float(b)])
        except Exception as e:
            continue

    # Create image assembly list
    _, indices = tree.query(target_lab)
    list_file = "match_list.txt"
    with open(list_file, "w") as f:
        for idx in indices:
            f.write(f'"{os.path.abspath(filenames[idx])}"\n')

    # Assemble image based on assembly list
    subprocess.run([
        "magick", "montage", "@match_list.txt",
        "-tile", f"{grid_size[0]}x{grid_size[1]}",
        "-geometry", "32x32+0+0", 
        output_name
    ])
    
    # Clean up temp files
    if os.path.exists(list_file): os.remove(list_file)


def main():
    if not os.path.exists(PKL_PATH):
        build_and_save_library(IMAGE_DIR, PKL_PATH) # Total Time = ~3 mins
    
    generate_mosaic(TARGET_IMAGE, PKL_PATH, OUTPUT_IMAGE, GRID_SIZE)

if __name__ == '__main__':
    main()
