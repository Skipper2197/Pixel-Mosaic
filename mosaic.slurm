#!/bin/bash
#SBATCH --job-name=Pixel_Mosaic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=01:00:00
#SBATCH --mem=64G
#SBATCH --mail-type=FAIL,BEGIN,END
#SBATCH --mail-user=incullicott@wm.edu               # change this!
#SBATCH -o /sciclone/home/incullicott/Pixel-Mosaic/pixel_%j.out # change this!
#SBATCH -e /sciclone/home/incullicott/Pixel-Mosaic/pixel_%j.err # change this!

# Load the conda/mamba module
module load miniforge3
source "$(conda info --base)/etc/profile.d/conda.sh"

ENV_NAME="mosaic-env"

if conda info --envs | grep -q "$ENV_NAME"; then
    echo "Environment '$ENV_NAME' already exists. Activating..."
else
    echo "Environment '$ENV_NAME' not found. Creating it now..."
    # Create the environment with all necessary tools
    mamba create -y -n $ENV_NAME \
        python=3.11 \
        numpy \
        scipy \
        scikit-image \
        tqdm \
        imagemagick \
        pillow \
        -c conda-forge
fi

# 3. Activate and Run
conda activate $ENV_NAME

python src/main.py

