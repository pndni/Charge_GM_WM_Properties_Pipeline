#!/bin/bash
#
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=40
#SBATCH --time=6:00:00
#SBATCH --job-name charge

# This file is derived from examples at
# https://docs.scinet.utoronto.ca/index.php/Running_Serial_Jobs_on_Niagara

# TODO: set sbatch options above based on your system

# TODO: setup either run_subject.sh or run_subject_container.sh for your site.
# see the comments in the respective file for details

# TODO: create a file "subject_list" that contains one subject name on each line
# each subject name is an argument to either run_subject.sh or run_subject_container.sh

# TODO: this line will likely be different based on your system
module load gnu-parallel

# TODO if not using singularity:
# export CHARGEDIR= # set to repository location

HOSTS=$(scontrol show hostnames $SLURM_NODELIST | tr '\n' ,)

# with singularity
parallel -j $SLURM_NTASKS_PER_NODE --joblog slurm_parallel_${SLURM_JOBID}.log -S $HOSTS --wd $PWD ./run_subject_container.sh {} :::: subject_list
# without singularity
# parallel -j $SLURM_NTASKS_PER_NODE --joblog slurm_parallel_${SLURM_JOBID}.log -S $HOSTS --wd $PWD --env CHARGEDIR ./run_subject.sh {} :::: subject_list
