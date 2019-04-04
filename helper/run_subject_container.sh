#!/bin/bash

set -e
set -u

subject=$1


# TODO: set these values based on your file naming scheme
# These should be the base filename only, not the full path
t1=${subject}_t1w.nii
dti=${subject}_dti.nii
bvec=${subject}.bvec
bval=${subject}.bval

indir=  # TODO: set the input directory (e.g. /projects/charge/$subject)
outdir=  # TODO: set to output directory (e.g. /projects/charge_output/$subject)

outdirbase=${outdir%/*}
outdirlast=${outdir##*/}

# TODO: freesurfer license:
# Copy the your freesurfer license to the output directory
# so it is visible from inside the container

/opt/singularity/bin/singularity run \
--bind $indir:/mnt/indir:ro \
--bind ${outdirbase}:/mnt/outdir \
--app charge \
--containall \
charge_container.simg -q -f /mnt/outdir/license.txt /mnt/indir $t1 /mnt/outdir/$outdirlast $dti $bvec $bval
