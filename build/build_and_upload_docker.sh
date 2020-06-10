#!/bin/bash

set -e
set -u

ver=$1
tmpdir=$(mktemp -d)

git clone --branch $ver git@github.com:pndni/Charge_GM_WM_Properties_Pipeline.git $tmpdir
pushd $tmpdir

docker build -t pndni/charge_gm_wm_properties_pipeline:$ver .
docker push pndni/charge_gm_wm_properties_pipeline:$ver
