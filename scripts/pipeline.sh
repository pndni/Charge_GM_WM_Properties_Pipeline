#!/bin/bash

set -e  # exit on error
set -u  # exit on undefined variable
\unalias -a  # remove all aliases (e.g. some systems alias 'cp' to 'cp -i')

version=1.0.0-alpha8

error() {
  >&2 echo $1
  exit 1
}



# Calculate and store hash of this file for logging and reproducibility

selfhash=$(sha256sum $0)


qc=0
while getopts qf: name
do
    case $name in
	q) qc=1
	   ;;
	f) export FS_LICENSE="$OPTARG"
	   ;;
	?) >&2 echo "Usage: pipeline.sh [-q] [-f freesurfer_license] indir t1 outdir [dti bvec bval]"
	   exit 2
	   ;;
    esac
done
shift $((OPTIND - 1))
indir="$1"
shift
t1="$1"
shift
outdir="$1"
shift
rundti=
if [ $# == 3 ]
then
    rundti=1
    dti="$1"
    bvec="$2"
    bval="$3"
elif [ $# != 0 ]
then
    error "Usage: pipeline.sh [-q] [-f freesurfer_license] indir t1 outdir [dti bvec bval]"
fi

if [ -d "$outdir" ]
then
    error "Output director already exists. Aborting"
fi

mkdir "$outdir"
pushd "$outdir" > /dev/null

# Check FSLOUTPUTTYPE and store appropriate extension in "ext"

case "$FSLOUTPUTTYPE" in
    NIFTI_GZ)
	ext=".nii.gz"
	;;
    NIFTI)
	ext=".nii"
	;;
    *)
	error "Unsupported value for FSLOUTPUTTYPE: $FSLOUTPUTTYPE . Aborting"
	;;
esac


qcappend(){
    # this horrible function simply inserts the contents of the file given by $1
    # before the </body> tag in $qcoutdir/index.html
    sed -i "/<\/body>/{
r ${1}
a<\/body>
d
}" "$qcoutdir"/index.html
}

#QC wrapper function
qcrun(){
    if [ $qc -eq 1 ]
    then
	local out
	out=$(fslpython "$CHARGEDIR/QC/makeqc.py" "$@") || error "QC error"
	qcappend "$out" || error "QC append error"
    fi
}

# wrapper function that handles redirection
logcmd(){
    #https://stackoverflow.com/questions/692000/how-do-i-write-stderr-to-a-file-while-using-tee-with-a-pipe
    #thanks to lhunath
    mkdir -p logs
    local logbase
    logbase=logs/$1
    shift
    echo "Running: " "$@" " > >(tee ${logbase}_stdout.txt) 2> >(tee ${logbase}_stderr.txt >&2)"
    "$@" > >(tee ${logbase}_stdout.txt) 2> >(tee ${logbase}_stderr.txt >&2) || error "logcmd $1"
}

# Copy input files

cp "$indir/$t1" ./

atlas="$CHARGEDIR"/models/atlas_labels_ref.nii.gz
brainmask="$CHARGEDIR"/models/icbm_mask_ref.nii.gz

#included with FSL
mnirefbrain="${FSLDIR}"/data/standard/MNI152_T1_2mm_brain.nii
if [ ! -e "$mnirefbrain" ]
then
    mnirefbrain="${mnirefbrain}".gz
    if [ ! -e "$mnirefbrain" ]
    then
       error "MNI152_T1_2mm_brain not found"
    fi
fi
mniref="${FSLDIR}"/data/standard/MNI152_T1_2mm.nii
if [ ! -e "$mniref" ]
then
    mniref="${mniref}".gz
    if [ ! -e "$mniref" ]
    then
       error "MNI152_T1_2mm not found"
    fi
fi
fnirtconf="${FSLDIR}"/etc/flirtsch/T1_2_MNI152_2mm.cnf

csf=0
gm=1
wm=2

t1betdir=t1_bet_out
t1cskull=t1_cropped_skull$ext
t1c=t1_cropped$ext
t1betimage="$t1betdir"/bet$ext
t1betimagecskull="$t1betdir"/bet_cropped_skull$ext
t1betimagec="$t1betdir"/bet_cropped$ext
t1skull="$t1betdir"/bet_skull$ext

t1fastdir=t1_fast_out
t1fastout="$t1fastdir"/t1
t1betcorc="${t1fastout}"_restore$ext
t1segc="${t1fastout}"_seg$ext
gmpvec=${t1fastout}_pve_${gm}$ext
wmpvec=${t1fastout}_pve_${wm}$ext
gmmask2=${t1fastout}_seg_${gm}_pv$ext
wmmask2=${t1fastout}_seg_${wm}_pv$ext

t1regdir=t1_reg_out
s2raff="$t1regdir"/struct2mni_affine.mat # affine matrix from the T1 image to the MNI reference
s2rwarp="$t1regdir"/struct2mni_warp$ext # warp transformation from the T1 image to the MNI reference
r2swarp="$t1regdir"/mni2struct_warp$ext # warp transformation from the MNI reference to the T1 image
t1betcorref="$t1regdir"/t1_bet_cor_ref$ext # betcor transformed to MNI coords
atlas_native="$t1regdir"/atlas_labels_native$ext
brainmask_native="$t1regdir"/icbm_mask_native$ext

nuoutdir=t1_nucor_out
nucor="$nuoutdir"/nu$ext
nucorcskull="$nuoutdir"/nu_cropped_skull$ext
nucorc="$nuoutdir"/nu_cropped$ext

statsdir=stats_out
statsfile="$statsdir"/stats.txt
statsfile_simple="$statsdir"/stats_simple.txt
#statsfile2=$statsdir/stats_wmprobmap.txt
gm_atlas="$statsdir"/gm_atlas$ext
wm_atlas="$statsdir"/wm_atlas$ext
# gm_atlas2=$statsdir/gm_atlas_pv$ext
# wm_atlas2=$statsdir/wm_atlas_pv$ext
combined_atlas="$statsdir"/combined_atlas$ext
# combined_atlas2=$statsdir/combined_atlas_pv$ext
atlas_lobe_gm="$statsdir"/atlas_lobe_gm$ext
atlas_lobe_wm="$statsdir"/atlas_lobe_wm$ext
# atlas_lobe_gm2=$statsdir/atlas_lobe_gm_pv$ext
# atlas_lobe_wm2=$statsdir/atlas_lobe_wm_pv$ext
simple_atlas="$statsdir"/atlas_simple$ext
# simple_atlas2=$statsdir/atlas_simple_pv$ext

qcoutdir=QC
if [ $qc == 1 ]
then
    mkdir "$qcoutdir"
    cp "$CHARGEDIR"/QC/boilerplate.html "$qcoutdir"/index.html
fi



# Options


t1bet_f=0.4  # parameter passed to FSL's  bet
croppad1=40  # amount to pad image when cropping to skull estimate
croppad2=10  # amount to pad image when cropping to T1
t1tissuefrac=0.9  # fraction of voxel that must be a tissue type for that voxel to be included in the tissue mask

# BET
#    Extract the brain from the image

# Do bet
mkdir "$t1betdir"
logcmd betlog bet "$t1" "$t1betimage" -f "$t1bet_f" -R -s
qcrun fade "T1" "BET" "$t1" "$t1betimage" "$qcoutdir" --logprefix logs/betlog


# Crop image
lims=( $(fslstats "$t1skull" -w) )
sizepad=$((croppad1 * 2))
xmin=$((lims[0] - croppad1))
xsize=$((lims[1] + sizepad))
ymin=$((lims[2] - croppad1))
ysize=$((lims[3] + sizepad))
zmin=$((lims[4] - croppad1))
zsize=$((lims[5] + sizepad))
logcmd t1croplog fslroi "$t1" "$t1cskull" $xmin $xsize $ymin $ysize $zmin $zsize
qcrun static "T1 crop 1" "$t1cskull" "$qcoutdir"
logcmd betcroplog fslroi "$t1betimage" "$t1betimagecskull" $xmin $xsize $ymin $ysize $zmin $zsize
qcrun static "BET crop 1" "$t1betimagecskull" "$qcoutdir"

lims2=( $(fslstats "$t1cskull" -w) )
sizepad=$((croppad2 * 2))
xmin2=$((lims2[0] - croppad2))
xsize2=$((lims2[1] + sizepad))
ymin2=$((lims2[2] - croppad2))
ysize2=$((lims2[3] + sizepad))
zmin2=$((lims2[4] - croppad2))
zsize2=$((lims2[5] + sizepad))
logcmd t1croplog2 fslroi "$t1cskull" "$t1c" $xmin2 $xsize2 $ymin2 $ysize2 $zmin2 $zsize2
qcrun static "T1 crop 2" "$t1c" "$qcoutdir"
logcmd betcroplog2 fslroi "$t1betimagecskull" "$t1betimagec" $xmin2 $xsize2 $ymin2 $ysize2 $zmin2 $zsize2
qcrun static "BET crop 2" "$t1betimagec" "$qcoutdir"

# Segmentation
#    Segment into white and grey matter. Simultaneously perform bias
#    field correction

mkdir "$t1fastdir"
logcmd fastlog fast --verbose --out="$t1fastout" -B --segments "$t1betimagec"
qcrun static "FAST classification" "$t1betcorc" "$qcoutdir" --label "$t1segc" --logprefix logs/fastlog

# Registration
#    Reference is MNI152 2mm standard

  

mkdir "$t1regdir"

# linear registration
#     register to ``brain only'' reference using the bet/bias corrected image (12 DOF)


logcmd flirtlog flirt -ref "$mnirefbrain" -in "$t1betcorc" -omat "$s2raff"
qcrun logs flirt logs/flirtlog "$qcoutdir"

# nonlinear registration
#     of original image to reference image
#     estimates bias field and nonlinear intensity mapping between images
#     Uses linear registration as initial transformation


logcmd fnirtlog fnirt --in="$t1c" --config="$fnirtconf" --aff="$s2raff" --cout="$s2rwarp"
qcrun logs fnirt logs/fnirtlog "$qcoutdir"

# Transform the bet image to the standard for QC


logcmd t1_2_ref_log applywarp --ref="$mniref" --in="$t1betcorc" --out="$t1betcorref" --warp="$s2rwarp"
qcrun fade "T1 in ref coords" "MNI reference" "$t1betcorref" "$mniref" "$qcoutdir" --logprefix=logs/t1_2_ref_log 

# Calculate inverse transformation

logcmd invwarplog invwarp --ref="$t1betcorc" --warp="$s2rwarp" --out="$r2swarp"
qcrun logs invwarp logs/invwarplog "$qcoutdir"

# apply inverse transformation to labels and brainmask
#    use nearest neighbor interpolation

logcmd atlas_2_native_log applywarp --ref="$t1betcorc" --in="$atlas" --out="$atlas_native" --warp="$r2swarp" --interp=nn --datatype=int
qcrun static "Lobe mask in native coords." "$t1betcorc" "$qcoutdir" --labelfile "$atlas_native" --logprefix logs/atlas_2_native_log
logcmd brainmask_2_native_log applywarp --ref="$t1betcorc" --in="$brainmask" --out="$brainmask_native" --warp="$r2swarp" --interp=nn --datatype=int
qcrun static "Brain mask in native coords." "$t1betcorc" "$qcoutdir" --labelfile "$brainmask_native" --logprefix logs/brainmask_2_native_log

# Sanity check

read atlas_min atlas_max <<< $(fslstats "$atlas_native" -R)
if [[ ! "$atlas_min" =~ ^0\.0*$ ]]
then
   error "Error with atlas label file. Aborting"
fi
if [[ ! "$atlas_max" =~ ^14\.0*$ ]];
then
   error "Error with atlas label file. Aborting"
fi

nlabels_atlas=$(fslpython "$CHARGEDIR"/utils/nlabels.py "$atlas_native") || error "nlabels error"
if [ $nlabels_atlas -ne 14 ]
then
    error "Transformed atlas has the incorrect number of labels. Probably an error with the transformation. Aborting"
fi
nlabels_brain=$(fslpython "$CHARGEDIR"/utils/nlabels.py "$brainmask_native") || error "nlabels error"
if [ $nlabels_brain -ne 1 ]
then
    error "Transformed brain mask has the incorrect number of labels. Probably an error with the transformation. Aborting"
fi

# ensure brain mask is not clipped
# this check doesn't make a lot of sense now that I've changed how the cropping
# works, but I'm leaving it in because it should still be true, and if this check
# fails something has gone horribly wrong
logcmd checkedgeslog fslpython "$CHARGEDIR"/utils/check_edges.py "$brainmask_native"

# MINC intensity correction


mkdir "$nuoutdir"
logcmd nucorrectlog mri_nu_correct.mni --i "$t1" --o "$nucor"
logcmd nucroplog fslroi "$nucor" "$nucorcskull" $xmin $xsize $ymin $ysize $zmin $zsize
logcmd nucroplog fslroi "$nucorcskull" "$nucorc" $xmin2 $xsize2 $ymin2 $ysize2 $zmin2 $zsize2
qcrun fade "T1" "NU corrected T1" "$t1c" "$nucorc" "$qcoutdir" --logprefix=logs/nucorrectlog

# Calculate intensity values


mkdir "$statsdir"



# create tissue masks by threshold partial volume images
fslmaths $gmpvec -thr $t1tissuefrac -bin $gmmask2
fslmaths $wmpvec -thr $t1tissuefrac -bin $wmmask2

# Construct combined atlas by offsetting wm values by 14

fslmaths "$atlas_native" -mas "$gmmask2" "$gm_atlas" -odt int
fslmaths "$atlas_native" -add 14 -mas "$wmmask2" -mas "$atlas_native" "$wm_atlas" -odt int
fslmaths "$gm_atlas" -add "$wm_atlas" "$combined_atlas" -odt int

# Construct atlases combining front, parietal, occipital, and temporal lobes from both hemispheres

fslmaths "$combined_atlas" -uthr 8.5 -bin "$atlas_lobe_gm" -odt int
fslmaths "$combined_atlas" -thr 14.5 -uthr 22.5 -bin -mul 2 "$atlas_lobe_wm" -odt int
fslmaths "$atlas_lobe_gm" -add "$atlas_lobe_wm" "$simple_atlas" -odt int

# Actually calculate stats


declare -a label_names
label_names[1]=Frontal_r_gm
label_names[2]=Parietal_r_gm
label_names[3]=Temporal_r_gm
label_names[4]=Occipital_r_gm
label_names[5]=Frontal_l_gm
label_names[6]=Parietal_l_gm
label_names[7]=Temporal_l_gm
label_names[8]=Occipital_l_gm
label_names[9]=Cerebellum_l_gm
label_names[10]=Sub-cortical_l_gm
label_names[11]=Brainstem_l_gm
label_names[12]=Cerebellum_r_gm
label_names[13]=Sub-cortical_r_gm
label_names[14]=Brainstem_r_gm
label_names[15]=Frontal_r_wm
label_names[16]=Parietal_r_wm
label_names[17]=Temporal_r_wm
label_names[18]=Occipital_r_wm
label_names[19]=Frontal_l_wm
label_names[20]=Parietal_l_wm
label_names[21]=Temporal_l_wm
label_names[22]=Occipital_l_wm
label_names[23]=Cerebellum_l_wm
label_names[24]=Sub-cortical_l_wm
label_names[25]=Brainstem_l_wm
label_names[26]=Cerebellum_r_wm
label_names[27]=Sub-cortical_r_wm
label_names[28]=Brainstem_r_wm
label_names_simple=( gm wm )

statswrapper () {
    local out=
    if [ $3 == "--skew" ] || [ $3 == "--kurtosis" ] || [ $3 == "--median" ]
    then
	out=( $(fslpython "$CHARGEDIR"/utils/stats.py -K "$1" "$2" "$3") ) || error "pystatserror $1 $2"
    else
	out=( $(fslstats -K "$1" "$2" "$3") ) || error "fslstatserror $1 $2"
    fi
    [ ${#out[*]} == $4 ] || error "unexpected number of outputs"
    echo ${out[*]}
}

echotsv () {
    local arr=( $1 )
    local start=${2:-0}
    local skip=${3:-1}
    for ((i=$start; i < ${#arr[*]}; i+=$skip))
    do
	echo -ne "\t${arr[i]}"
    done
}

printstats() {
    local atlas="$1"
    local imagename="$2"
    local image="$3"
    local nlabels="$4"
    
    local rangetmp
    local rangebraintmp
    local voltmp
    local volbraintmp
    # mean
    echo -en "${imagename}_mean"
    echotsv "$(statswrapper "$atlas" "$image" -m $nlabels)" || error "echotsv"
    echo -e "\t"$(statswrapper "$brainmask_native" "$image" -m 1)

    # median
    echo -en "${imagename}_median"
    echotsv "$(statswrapper "$atlas" "$image" --median $nlabels)" || error "echotsv"
    echo -e "\t"$(statswrapper "$brainmask_native" "$image" --median 1)

    # std
    echo -en "${imagename}_std"
    echotsv "$(statswrapper "$atlas" "$image" -s $nlabels)" || error "echotsv"
    echo -e "\t"$(statswrapper "$brainmask_native" "$image" -s 1)

    # range
    rangetmp=$(statswrapper "$atlas" "$image" -R $((nlabels * 2))) || error "statswrapper"
    rangebraintmp=( $(statswrapper "$brainmask_native" "$image" -R 2) ) || error "statswrapper"
    echo -en "${imagename}_min"
    echotsv "$rangetmp" 0 2 || error "echotsv"
    echo -e "\t"${rangebraintmp[0]}
    echo -en "${imagename}_max"
    echotsv "$rangetmp" 1 2 || error "echotsv"
    echo -e "\t"${rangebraintmp[1]}

    # volume
    voltmp=$(statswrapper "$atlas" "$image" -v $((nlabels * 2))) || error "statswrapper"
    volbraintmp=( $(statswrapper "$brainmask_native" "$image" -v 2) ) || error "statswrapper"
    echo -en "${imagename}_nvoxels"
    echotsv "$voltmp" 0 2 || error "echotsv"
    echo -e "\t"${volbraintmp[0]}
    echo -en "${imagename}_volume"
    echotsv "$voltmp" 1 2 || error "echotsv"
    echo -e "\t"${volbraintmp[1]}

    # skew
    echo -en "${imagename}_skew"
    echotsv "$(statswrapper "$atlas" "$image" --skew $nlabels)" || error "echotsv"
    echo -e "\t"$(statswrapper "$brainmask_native" "$image" --skew 1)

    # kurtosis
    echo -en "${imagename}_kurtosis"
    echotsv "$(statswrapper "$atlas" "$image" --kurtosis $nlabels)" || error "echotsv"
    echo -e "\t"$(statswrapper "$brainmask_native" "$image" --kurtosis 1)
}

echo "# Data calculated using $(basename $0) with sha256 ${selfhash}"     > "$statsfile"
echo "# Version: $version"                                                >> "$statsfile"
echo "# Input directory: $indir"                                          >> "$statsfile"
echo "# T1 filename: $t1"                                                 >> "$statsfile"
echo "# DTI filename: $dti"                                               >> "$statsfile"
echo "# bvec: $bvec"                                                      >> "$statsfile"
echo "# bval: $bval"                                                      >> "$statsfile"
echo "# Onput directory: $outdir"                                         >> "$statsfile"
echo "# $(date)"                                                          >> "$statsfile"
echotsv "${label_names[*]}"                                               >> "$statsfile" || error "echotsv"
echo -e "\tBrain"                                                         >> "$statsfile"

printstats "$combined_atlas" "T1" "$nucorc" 28 >> "$statsfile" || error "printstats"
# printstats $combined_atlas "nocor" $t1c 28 >> $statsfile || error "printstats"
# printstats "pvatlas" $combined_atlas2 "cor" $nucorc 28 >> $statsfile || error "printstats"
# printstats "pvatlas" $combined_atlas2 "nocor" $t1c 28 >> $statsfile || error "printstats"

echo "# Data calculated using $(basename $0) with sha256 ${selfhash}"     > "$statsfile_simple"
echo "# Version: $version"                                                >> "$statsfile_simple"
echo "# Input directory: $indir"                                          >> "$statsfile_simple"
echo "# T1 filename: $t1"                                                 >> "$statsfile_simple"
echo "# DTI filename: $dti"                                               >> "$statsfile_simple"
echo "# bvec: $bvec"                                                      >> "$statsfile_simple"
echo "# bval: $bval"                                                      >> "$statsfile_simple"
echo "# Onput directory: $outdir"                                         >> "$statsfile_simple"
echo "# $(date)"                                                          >> "$statsfile_simple"
echotsv "${label_names_simple[*]}"                                        >> "$statsfile_simple" || error "echotsv"
echo -e "\tBrain"                                                         >> "$statsfile_simple"

printstats "$simple_atlas" "T1" "$nucorc" 2 >> "$statsfile_simple" || error "printstats"
# printstats $simple_atlas "nocor" $t1c 2 >> $statsfile_simple || error "printstats"
# printstats "pvatlas" $simple_atlas2 "cor" $nucorc 2 >> $statsfile_simple || error "printstats"
# printstats "pvatlas" $simple_atlas2 "nocor" $t1c 2 >> $statsfile_simple || error "printstats"

# DTI

# adapted from psmd.sh

# Setup

if [ ! -z "$rundti" ]
then
    
    # Copy input files
    
    
    \cp "$indir/$dti" ./
    \cp "$indir/$bvec" ./
    \cp "$indir/$bval" ./
    
    # Create variables
    
    dtibetdir=dti_bet_out
    dtibetimage="$dtibetdir"/bet$ext
    dtibetmask="$dtibetdir"/bet_mask$ext
    
    eddycordir=dti_eddy_out
    eddycorimage="$eddycordir"/eddycor
    
    dtifitdir=dti_fit_out
    dtifitbase="$dtifitdir"/dti
    dtifa="${dtifitbase}"_FA$ext
    dtimd="${dtifitbase}"_MD$ext
    
    dtiregdir=dti_reg_out
    structforreg="$dtiregdir"/dti_struct_for_reg$ext
    dti2t1="$dtiregdir"/dti2struct_affine.mat
    struct_native="$dtiregdir"/dti_struct_native$ext
    dtifa_native="$dtiregdir"/dti_FA_native$ext
    dtimd_native="$dtiregdir"/dti_MD_native$ext
    
    # Eddy correction
    
    mkdir "$eddycordir"
    
    
    # This registers everything to the reference frame using the correlation ratio
    # cost function and a linear transformation (flirt). The structural image is found
    # by looking for 0 in the bval file.
    
    
    
    refinds=( $(tr ' ' '\n' < "$bval" | awk 'NF > 0 && ($1 + 0) == 0 {print NR - 1}') ) || error "refinds calc"
    if [ ${#refinds[@]} -ne 1 ]
    then
        error "dti scan must contain exactly one structural (reference) image"
    fi
    echo "Structural scan found at index $refinds of $dti"
    logcmd eddycorrectlog eddy_correct "$dti" "$eddycorimage" $refinds
    qcrun logs "Eddy correct" logs/eddycorrectlog "$qcoutdir"
    
    # BET 
    
    mkdir "$dtibetdir"
    
    
    
    # #+RESULTS:
    
    
    logcmd dtibetlog bet "$eddycorimage" "$dtibetimage" -m -F
    qcrun logs "DTI BET" logs/dtibetlog "$qcoutdir"
    
    # DTIFIT
    
    
    mkdir "$dtifitdir"
    
    # I switched input from dtibetimage to eddycorimage, which
    # I think is better and more like what psmd does.
    logcmd dtifitlog dtifit --data="$eddycorimage" --out="$dtifitbase" --mask="$dtibetmask" --bvecs="$bvec" --bvals="$bval"
    qcrun logs "DTI Fit" logs/dtifitlog "$qcoutdir"
    qcrun static "DTI Fit: FA" "$dtifa" "$qcoutdir"
    qcrun static "DTI Fit: MD" "$dtimd" "$qcoutdir"
    
    # Registration
    
    
    mkdir "$dtiregdir"
    
    logcmd dtibetroilog fslroi "$dtibetimage" "$structforreg" $refinds 1
    logcmd dtiflirtlog flirt -ref "$t1betcorc" -in "$structforreg" -omat "$dti2t1" -out "$struct_native"
    qcrun fade "T1" "DTI struct reference in T1 coords" "$nucorc" "$struct_native" "$qcoutdir" --logprefix logs/dtiflirtlog
    logcmd dtifatransformlog flirt -ref "$t1betcorc" -init "$dti2t1" -applyxfm -in "$dtifa" -out "$dtifa_native"
    qcrun fade "T1" "FA in T1 coords" "$nucorc" "$dtifa_native" "$qcoutdir" --logprefix logs/dtifatransformlog
    logcmd dtimdtransformlog flirt -ref "$t1betcorc" -init "$dti2t1" -applyxfm -in "$dtimd" -out "$dtimd_native"
    qcrun fade "T1" "MD in T1 coords" "$nucorc" "$dtimd_native" "$qcoutdir" --logprefix logs/dtimdtransformlog
    qcrun static "Brain mask over FA" "$dtifa_native" "$qcoutdir" --labelfile "$brainmask_native"
    qcrun static "Brain mask over MD" "$dtimd_native" "$qcoutdir" --labelfile "$brainmask_native"
    qcrun static "Lobe mask over FA" "$dtifa_native" "$qcoutdir" --labelfile "$atlas_native"
    qcrun static "Lobe mask over MD" "$dtimd_native" "$qcoutdir" --labelfile "$atlas_native"
    
    # Data extraction
    
    
    printstats "$combined_atlas" "FA" "$dtifa_native" 28 >> "$statsfile" || error "printstats"
    printstats "$combined_atlas" "MD" "$dtimd_native" 28 >> "$statsfile" || error "printstats"
    # printstats "pvatlas" $combined_atlas2 "FA" $dtifa_native 28 >> $statsfile || error "printstats"
    # printstats "pvatlas" $combined_atlas2 "MD" $dtimd_native 28 >> $statsfile || error "printstats"
    
    
    printstats "$simple_atlas" "FA" "$dtifa_native" 2 >> "$statsfile_simple" || error "printstats"
    printstats "$simple_atlas" "MD" "$dtimd_native" 2 >> "$statsfile_simple" || error "printstats"
    # printstats "pvatlas" $simple_atlas2 "FA" $dtifa_native 2 >> $statsfile_simple || error "printstats"
    # printstats "pvatlas" $simple_atlas2 "MD" $dtimd_native 2 >> $statsfile_simple || error "printstats"
fi

# Cleanup
ERROR=0
WARNING=0
if cat logs/*stderr.txt | grep -v -e '^Saving result to .* (type = MINC )\s*\[ ok \]$' > /dev/null
then
    # something was found in stderr
    echo "2: ERROR. stderr output indicates error" > status.txt
    ERROR=1
else
    echo "0: stderr output does not indicate error" > status.txt
fi
if grep -e '^Warning, Jacobian not within prescribed range' logs/fnirtlog_stdout.txt > /dev/null
then
    WARNING=1
    
    if ! grep -e '^Warning, Jacobian not within prescribed range' logs/fnirtlog_stdout.txt | awk '($(16) < -0.5) {exit 1}'
    then
	ERROR=1
	echo "2: ERROR. logs/fnirtlog_stdout.txt indicates jacobian determinent is well outside prescribed range. Check registrations" >> status.txt
    else
	echo "1: WARNING. logs/fnirtlog_stdout.txt indicates a warning with Jacobians. Check registrations" >> status.txt
    fi
else
    echo "0: logs/fnirtlog_stdout.txt indicates no warnings or errors" >> status.txt
fi
echo $ERROR > errorflag
echo $WARNING > warningflag

popd > /dev/null

exit $ERROR
