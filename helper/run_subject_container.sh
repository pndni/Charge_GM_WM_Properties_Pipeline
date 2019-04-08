#!/bin/bash

set -e
set -u

subject="$1"

indir=  # TODO: set the input directory (e.g. /projects/charge/$subject)
outdir=  # TODO: set to output directory (e.g. /projects/charge_output/$subject)
logdir=  # TODO: set log directory (e.g. /projects/charge_output/logs).
         # log files will be ${subject}_stdout.log and ${subject}_stderr.log

# TODO: set these values based on your file naming scheme
# These should be the base filename only, not the full path
t1="$subject"_t1w.nii
dti="$subject"_dti.nii
bvec="$subject".bvec
bval="$subject".bval

outdirbase="${outdir%/*}"
outdirlast="${outdir##*/}"


# TODO: freesurfer license:
# Copy the your freesurfer license to the output directory
# so it is visible from inside the container

singularity run \
--bind "$indir":/mnt/indir:ro \
--bind "$outdirbase":/mnt/outdir \
--app charge \
--containall \
charge_container.simg -q -f /mnt/outdir/license.txt \
/mnt/indir \
"$t1" \
/mnt/outdir/"$outdirlast" \
"$dti" \
"$bvec" \
"$bval" \
> "$logdir"/"$subject"_stdout.log \
2> "$logdir"/"$subject"_stderr.log
