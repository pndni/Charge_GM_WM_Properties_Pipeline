#!/bin/bash

set -e

## TODO
# if necessary, setup FSL and freesurfer here
# for example:
# FREESURFER_HOME="TODO path to freesurfer"
# source $FREESURFER_HOME/SetUpFreeSurfer.sh
# FSLDIR="TODO path to fsl"
# source $FSLDIR/etc/fslconf/fsl.sh

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

$CHARGEDIR/scripts/pipeline.sh -q $indir $t1 $outdir $dti $bvec $bval
