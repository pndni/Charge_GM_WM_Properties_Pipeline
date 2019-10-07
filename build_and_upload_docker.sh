#!/bin/bash

set -e
set -u

ver=$1
tmpdir=$(mktemp -d)

git clone git@github.com:pndni/Charge_GM_WM_Properties_Pipeline.git $tmpdir
pushd $tmpdir
git checkout $ver

docker build --label org.opencontainers.image.revision=$ver --label org.opencontainers.image.build-date="$(date --rfc-3339=seconds)" --label org.opencontainers.image.version=$ver -t pndni/charge_gm_wm_properties_pipeline:$ver .
docker push pndni/charge_gm_wm_properties_pipeline:$ver
