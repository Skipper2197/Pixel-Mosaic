# Pixel-Mosaic

A photomosaic generator that reproduces a target image by tiling thousands of smaller images together. The pipeline downloads AI-generated face images, builds a perceptually-accurate color index, and assembles a high-resolution mosaic. Designed to run both locally and on the SciClone HPC cluster.

---

## How It Works

The pipeline runs in three phases:

**Phase 1 — Data Acquisition** (`01_`): Downloads image datasets from Kaggle (e.g. AI-generated faces, flowers, nature photos). Each image is validated with ImageMagick and saved to `data/raw/`.

**Phase 2 — Tile Library** (`02_`, `02b_`): Each dataset's images are resized to square thumbnails (default 32×32 px) and stored in their own subdirectory under `data/thumbnails/` (e.g. `face_thumbnails/`, `flowers_thumbnails/`). The average LAB color of each thumbnail's center is computed across all selected datasets and stored in a k-d tree, which is pickled (saved as a binary `.pkl` file) to `color_trees/`. This database is built once and reused for every mosaic.

**Phase 3 — Mosaic Generation** (`03_`): The target image is downsampled to a grid (default 100×100 cells). Each cell's color is matched against the k-d tree to find the closest tile. The matched tiles are assembled on a canvas and saved as a JPEG.

### Why LAB instead of RGB?

Euclidean distance in RGB doesn't match how humans perceive color — a small numerical change in green looks much more noticeable than the same change in blue. The LAB colorspace is designed so that equal numerical distances correspond to equal perceptual differences, meaning the "closest" tile in LAB space is actually the closest-looking tile to a human eye.

### Why a k-d tree?

A brute-force search against 50,000 tiles for each cell of a 100×100 grid would require 500 million distance comparisons per mosaic. A k-d tree organizes the color space into nested regions, reducing lookups to roughly O(N log M) — over 1,000× faster.

### Why center-crop when indexing tiles?

Face images have significant background and clothing around the subject. Cropping to the center 50% biases the average color toward the face itself, producing better color matches in the final mosaic.

---

## Output Example

**Target Image:**

![Target](data/target/dwayne-johnson-walk-of-fame-honor.webp)

**Mosaic Output:**

![Mosaic](output/mosaic_lab_slurm_flowers.jpg)

---

## Project Structure

```text
Pixel-Mosaic/
│
├── pipeline.sh                  # Top-level orchestrator — run this
├── mosaic.slurm                 # SLURM job script for SciClone
├── environment.yaml             # Conda environment definition
│
├── scripts/                     # Bash wrappers for each pipeline stage
│   ├── 01_download_clean.sh     # Stage 1: Download and validate face images
│   ├── 02_build_thumbnails.sh   # Stage 2: Resize images to square tiles
│   ├── 02b_build_database.sh    # Stage 2b: Build LAB k-d tree → color_tree.pkl
│   └── 03_generate_mosaic.sh    # Stage 3: Generate the mosaic JPEG
│
├── src/                         # Python source modules
│   ├── common.py                # Shared constants and LAB color utilities
│   ├── build_thumbnails.py      # Stage 2 logic
│   ├── build_database.py        # Stage 2b logic
│   ├── generate_mosaic.py       # Stage 3 logic
│   ├── rgb.py                   # Early RGB prototype (not used by pipeline)
│   └── lab.py                   # Early LAB prototype (not used by pipeline)
│
├── data/                        # All data files (mostly gitignored)
│   ├── raw/                     # Downloaded zips + extracted images
│   ├── thumbnails/              # 32×32 tiles, one subdir per dataset
│   │   ├── face_thumbnails/     # AI-generated faces
│   │   └── flowers_thumbnails/  # flower photos (and other datasets)
│   └── target/                  # Target image(s) to mosaicify
│
├── color_trees/                 # Pickled k-d tree databases (.pkl, gitignored)
│
└── output/                      # Generated mosaics (gitignored)
```

> `data/raw/`, `data/thumbnails/`, `color_trees/*.pkl`, and `output/` are all gitignored and will not be committed.

---

## Setup

### Prerequisites

| Requirement | Notes |
|---|---|
| Conda / Miniforge | On SciClone: `module load miniforge3`. Locally: install [Miniforge](https://github.com/conda-forge/miniforge). |
| Kaggle API token | Required to download datasets. See below. |
| ImageMagick | Used for image validation. Installed automatically into `mosaic_env`. |

### Kaggle API Token

1. Go to [kaggle.com/settings](https://www.kaggle.com/settings) → **API** → **Create New Token**. This downloads a `kaggle.json` file containing your token.
2. Add the following to your `~/.bashrc`:

```bash
export KAGGLE_API_TOKEN=your_token_here
```

3. Reload your shell: `source ~/.bashrc`

The download scripts check for this variable at startup and exit with a clear error if it's missing.

### Conda Environment

The conda environment (`mosaic_env`) is created automatically the first time `02_build_thumbnails.sh` runs. To create it manually:

```bash
mamba env create -f environment.yaml
conda activate mosaic_env
```

The environment includes: Python 3.12, NumPy, SciPy, scikit-image, Pillow, and tqdm.

---

## Running the Pipeline

### Using Multiple Datasets

The pipeline supports building a mosaic from more than one image dataset. Each dataset gets its own subdirectory under `data/thumbnails/` (e.g. `face_thumbnails/`, `flowers_thumbnails/`). When building the k-d tree, `02b_build_database.sh` points at whichever thumbnail directories you want to include — combining them produces a richer, more colorful tile library. See the `--thumb-dir` argument in `src/build_database.py` for how to specify multiple sources.

### Quickstart

1. Place your target image in `data/target/`.
2. Edit the `USER SETTINGS` block at the top of `pipeline.sh`:

```bash
SUBSET=500                           # images to use (500 for testing, 10000+ for quality)
TARGET="data/target/your_image.jpg"  # path to your target image
GRID_SIZE=100                        # cells per side of the mosaic grid
TILE_SIZE=32                         # pixel size of each tile
```

3. Run from the project root:

```bash
bash pipeline.sh
```

4. The output will be at `output/mosaic_<target-name>.jpg`.

### Idempotency

Every stage is idempotent — re-running `pipeline.sh` skips work that's already done:

- Downloads are guarded by stamp files inside `data/raw/`. Delete the stamp to force a re-download.
- Thumbnails are skipped if the file already exists in its dataset subdirectory under `data/thumbnails/`.
- The k-d tree pickle is skipped if it already exists in `color_trees/`. Pass `--force` to `02b_build_database.sh` to rebuild it.
- Stage 3 (mosaic generation) always reruns, since iterating on the final image is the typical workflow.

### Running Individual Stages

Once the tile library is built, you can generate a new mosaic without re-running the full pipeline:

```bash
bash scripts/03_generate_mosaic.sh data/target/new_image.jpg --grid-size 150
```

---

## Script Reference

| Script | Purpose | Key flags |
|---|---|---|
| `pipeline.sh` | Runs all stages in order | Edit `USER SETTINGS` at the top |
| `01_download_clean.sh` | Downloads and validates face images | `--subset N` |
| `02_build_thumbnails.sh` | Resizes images to square tiles; creates conda env | `--tile-size N` |
| `02b_build_database.sh` | Builds LAB k-d tree and pickles it | `--force` |
| `03_generate_mosaic.sh` | Generates the final mosaic | `<target> --grid-size N --tile-size N` |

---

## HPC / SLURM

`mosaic.slurm` submits the full pipeline to SciClone as a batch job. It requests 32 CPUs and 64 GB of RAM. The Python code reads `$SLURM_CPUS_PER_TASK` automatically to set the number of parallel tile-loading workers, so the CPU count only needs to be set in one place.

```bash
# Edit --mail-user in mosaic.slurm first, then:
sbatch mosaic.slurm

# Monitor your job
squeue -u $USER
tail -f output/pixel_<JOBID>.out
```

All data paths in the SLURM workflow point to the shared scratch directory (`/sciclone/scr10/gzdata440/Pixel-Mosaic/data`) so the full dataset doesn't need to be duplicated per user.

---

## Tuning the Output

| Parameter | Effect | Tradeoff |
|---|---|---|
| `SUBSET` | More tiles → better color matching | Larger datasets take longer to download and index |
| `GRID_SIZE` | Higher grid → finer detail | Canvas grows as `GRID_SIZE² × TILE_SIZE²` pixels |
| `TILE_SIZE` | Larger tiles → individual photos more visible | Needs a smaller grid to stay manageable |

**Recommended settings for a quality output on SciClone:**
```bash
SUBSET=10000
GRID_SIZE=150
TILE_SIZE=32
```

This produces a 4,800×4,800 px canvas from 22,500 tile placements, drawing from a library of 10,000 unique photos.

---

## Quick Reference

```bash
# Run the full pipeline
bash pipeline.sh

# Generate a new mosaic from an existing tile library
bash scripts/03_generate_mosaic.sh data/target/myimage.jpg

# Force rebuild the k-d tree (e.g. after adding new tiles)
bash scripts/02b_build_database.sh --force

# Submit to HPC
sbatch mosaic.slurm
```