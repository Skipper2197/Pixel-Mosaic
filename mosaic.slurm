#!/bin/bash
# =============================================================================
# mosaic.slurm
# SLURM job script for the Pixel-Mosaic pipeline on SciClone.
#
# Submits pipeline.sh as a batch job. The key resource request is
# --cpus-per-task=32, which SLURM exposes as the environment variable
# SLURM_CPUS_PER_TASK. generate_mosaic.py reads this variable to set
# the number of multiprocessing workers, so the Python code and the
# SLURM request stay in sync automatically — no need to hardcode
# worker counts in two places.
#
# Usage:
#   cd ~/Pixel-Mosaic
#   sbatch mosaic.slurm
#
# Monitor:
#   squeue -u $USER
#   sacct -j <JOBID>
#   tail -f output/pixel_<JOBID>.out
# =============================================================================

#SBATCH --job-name=Pixel_Mosaic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=01:00:00
#SBATCH --mem=64G
#SBATCH --mail-type=FAIL,BEGIN,END
#SBATCH --mail-user=ajblenke@wm.edu
#SBATCH -o output/pixel_%j.out
#SBATCH -e output/pixel_%j.err

# ---------------------------------------------------------------------------
# Environment setup
#
# SLURM starts the job in the directory you ran 'sbatch' from, which
# should be ~/Pixel-Mosaic (the project root). pipeline.sh verifies
# this with its own sanity check.
#
# 'module load miniforge3' puts conda on PATH but does not enable
# 'conda activate'. The second line sources the shell hook so that
# activation works. Same pattern as 02_build_thumbnails.sh — see
# that file for the full explanation.
# ---------------------------------------------------------------------------
echo "Job $SLURM_JOB_ID starting on $(hostname) at $(date)"
echo "Working directory: $(pwd)"
echo "CPUs allocated: $SLURM_CPUS_PER_TASK"
echo ""

# Ensure the output directory exists for SLURM log files.
# SLURM creates the .out/.err files itself, but it needs the
# directory to already exist at submission time.
mkdir -p output

# ---------------------------------------------------------------------------
# Run the full pipeline
#
# pipeline.sh handles everything: conda activation, downloads,
# thumbnailing, database build, and mosaic generation. Each stage
# script loads its own conda environment internally, so we don't
# need to activate here.
# ---------------------------------------------------------------------------
bash pipeline.sh

echo ""
echo "Job $SLURM_JOB_ID finished at $(date)"
