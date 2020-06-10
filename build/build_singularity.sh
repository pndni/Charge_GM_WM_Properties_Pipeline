#!/bin/bash

set -eu

ver=$1

echo $PWD
tmpdir=$PWD/tmpdir
if [ -d $tmpdir ]; then
	rm -rf $tmpdir
fi
mkdir $tmpdir

dockerimg=pndni/charge_gm_wm_properties_pipeline:$ver

SINGULARITY_TMPDIR=$tmpdir
export SINGULARITY_TMPDIR

singularity build charge_container_$ver.simg docker://$dockerimg
rm -rf $SINGULARITY_TMPDIR
