#!/bin/bash

set -e  # exit on error
set -u  # exit on undefined variable
\unalias -a  # remove all aliases (e.g. some systems alias 'cp' to 'cp -i')

version=1.0.0-alpha10

error() {
  >&2 echo $1
  exit 1
}



# Calculate and store hash of this file for logging and reproducibility

selfhash=$(sha256sum $0)
fsversion=$(cat $FREESURFER_HOME/build-stamp.txt)
fslversion=$(cat $FSLDIR/etc/fslversion)
antsversion=$(antsRegistration --version | head -n 1)

usage="Usage: pipeline.sh [-q] [-f freesurfer_license] [-p phase_encoding_direction] indir t1 outdir [dti bvec bval [acqp index]]"

qc=0
useeddy=0
phase_enc=""
while getopts qf:p: name
do
    case $name in
	q) qc=1
	   ;;
	f) export FS_LICENSE="$OPTARG"
	   ;;
        p) phase_enc="$OPTARG"
           useeddy=1
           ;;
	?) >&2 echo $usage
	   exit 2
	   ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -ne 3 ] && [ $# -ne 6 ] && [ $# -ne 8 ]
then
    error "$usage"
fi
indir="$1"
shift
t1="$1"
shift
outdir="$1"
shift
rundti=
if [ $# -gt 0 ]
then
    rundti=1
    dti="$1"
    shift
    bvec="$1"
    shift
    bval="$1"
    shift
    if [ $# -eq 2 ]
    then
        if [ -n "$phase_enc" ]
        then
            error "either specify acqp and index or -p, not both"
        fi
        useeddy=1
        acqp="$1"
        index="$2"
    elif [ $# -ne 0 ]
    then
        error "$usage"
    fi
fi

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

if [ -e "$outdir" ]
then
    error "Output director already exists. Aborting"
fi

mkdir "$outdir"
pushd "$outdir" > /dev/null

qcoutdir=QC

# Copy input files

\cp "$indir/$t1" ./
if [ -n "$rundti" ]
then
    \cp "$indir/$dti" ./
    \cp "$indir/$bvec" ./
    \cp "$indir/$bval" ./

    if [ $useeddy -eq 1 ]
    then
        if [ -n "$phase_enc" ]
        then
            acqp="acqp.txt"
            index="index.txt"
            nvols=$(fslnvols "$dti")
            "$CHARGEDIR"/scripts/simple_eddy_cfg.sh "$phase_enc" $nvols $acqp $index
        else
            \cp "$indir/$acqp" ./
            \cp "$indir/$index" ./
        fi
    fi
fi

if [ $qc == 1 ]
then
    mkdir "$qcoutdir"
    cp "$CHARGEDIR"/QC/boilerplate.html "$qcoutdir"/index.html
fi

if [ $useeddy -eq 1 ]
then
    echo 1 > eddyflag
else
    echo 0 > eddyflag
fi



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
t1cskull="$t1betdir"/t1_cropped_skull$ext
t1c="$t1betdir"/t1_cropped$ext
t1betimage="$t1betdir"/bet$ext
t1betimagecskull="$t1betdir"/bet_cropped_skull$ext
t1betimagec="$t1betdir"/bet_cropped$ext
t1skull="$t1betdir"/bet_skull$ext
t1betmask="$t1betdir"/bet_mask$ext
t1betmaskcskull="$t1betdir"/bet_mask_cropped_skull$ext
t1betmaskc="$t1betdir"/bet_mask_cropped$ext

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
brainmask_native="$t1regdir"/brain_mask_native$ext

nuoutdir=t1_nucor_out
nucor="$nuoutdir"/nu$ext
nucorcskull="$nuoutdir"/nu_cropped_skull$ext
nucorc="$nuoutdir"/nu_cropped$ext
nucorcbrain="$nuoutdir"/nu_cropped_brain$ext

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
simple_atlas="$statsdir"/simple_atlas$ext
# simple_atlas2=$statsdir/atlas_simple_pv$ext



# Options


t1bet_f=0.4  # parameter passed to FSL's  bet
croppad1=40  # amount to pad image when cropping to skull estimate
croppad2=10  # amount to pad image when cropping to T1
t1tissuefrac=0.9  # fraction of voxel that must be a tissue type for that voxel to be included in the tissue mask

# BET
#    Extract the brain from the image

# Do bet
mkdir "$t1betdir"
logcmd betlog bet "$t1" "$t1betimage" -f "$t1bet_f" -R -s -m
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
logcmd betmaskcroplog fslroi "$t1betmask" "$t1betmaskcskull" $xmin $xsize $ymin $ysize $zmin $zsize
qcrun static "BET mask crop 1" "$t1betmaskcskull" "$qcoutdir"

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
logcmd betmaskcroplog2 fslroi "$t1betmaskcskull" "$t1betmaskc" $xmin2 $xsize2 $ymin2 $ysize2 $zmin2 $zsize2
qcrun static "BET mask crop 2" "$t1betmaskc" "$qcoutdir"

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
logcmd nucroplog2 fslroi "$nucorcskull" "$nucorc" $xmin2 $xsize2 $ymin2 $ysize2 $zmin2 $zsize2
qcrun fade "T1" "NU corrected T1" "$t1c" "$nucorc" "$qcoutdir" --logprefix=logs/nucorrectlog
logcmd numasklog fslmaths -dt double "$nucorc" -mas "$t1betmaskc" "$nucorcbrain" -odt double
qcrun fade "NU corrected T1" "NU corrected T1 brain" "$nucorc" "$nucorcbrain" "$qcoutdir" --logprefix=logs/numasklog

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
echo "# FreeSurfer Version: $fsversion"                                   >> "$statsfile"
echo "# FSL Version: $fslversion"                                         >> "$statsfile"
echo "# $antsversion"                                                     >> "$statsfile"
echo "# Input directory: $indir"                                          >> "$statsfile"
echo "# T1 filename: $t1"                                                 >> "$statsfile"
echo "# DTI filename: $dti"                                               >> "$statsfile"
echo "# bvec: $bvec"                                                      >> "$statsfile"
echo "# bval: $bval"                                                      >> "$statsfile"
echo "# Output directory: $outdir"                                         >> "$statsfile"
echo "# useeddy: $useeddy"                                                >> "$statsfile"
echo "# $(date)"                                                          >> "$statsfile"
echotsv "${label_names[*]}"                                               >> "$statsfile" || error "echotsv"
echo -e "\tBrain"                                                         >> "$statsfile"

printstats "$combined_atlas" "T1" "$nucorc" 28 >> "$statsfile" || error "printstats"
# printstats $combined_atlas "nocor" $t1c 28 >> $statsfile || error "printstats"
# printstats "pvatlas" $combined_atlas2 "cor" $nucorc 28 >> $statsfile || error "printstats"
# printstats "pvatlas" $combined_atlas2 "nocor" $t1c 28 >> $statsfile || error "printstats"

echo "# Data calculated using $(basename $0) with sha256 ${selfhash}"     > "$statsfile_simple"
echo "# Version: $version"                                                >> "$statsfile_simple"
echo "# FreeSurfer Version: $fsversion"                                   >> "$statsfile_simple"
echo "# FSL Version: $fslversion"                                         >> "$statsfile_simple"
echo "# $antsversion"                                                     >> "$statsfile_simple"
echo "# Input directory: $indir"                                          >> "$statsfile_simple"
echo "# T1 filename: $t1"                                                 >> "$statsfile_simple"
echo "# DTI filename: $dti"                                               >> "$statsfile_simple"
echo "# bvec: $bvec"                                                      >> "$statsfile_simple"
echo "# bval: $bval"                                                      >> "$statsfile_simple"
echo "# Output directory: $outdir"                                         >> "$statsfile_simple"
echo "# useeddy: $useeddy"                                                >> "$statsfile_simple"
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
    
    
    # Create variables
    
    dtibetdir=dti_bet_out
    dtib0="$dtibetdir"/dti_b0$ext
    dtib0betimage="$dtibetdir"/dti_b0_bet$ext
    dtib0betmask="$dtibetdir"/dti_b0_bet_mask$ext
    
    eddycordir=dti_eddy_out
    eddycorbase="$eddycordir"/eddycor
    eddycorimage="$eddycorbase"$ext
    bvecrot="$eddycorbase".eddy_rotated_bvecs
    eddylog="$eddycorbase".ecclog
    eddycorsplitdir="$eddycordir"/split
    
    dtiregdir=dti_reg_out
    nucorcbrainrs="$dtiregdir"/nu_cropped_brain_resampled$ext
    # structforreg="$dtiregdir"/dti_struct_for_reg$ext
    dti2t1="$dtiregdir"/dti2struct
    dti2t1_aff="$dti2t1"0GenericAffine.mat
    dti2t1_warp="$dti2t1"1Warp.nii.gz
    dtiregsplitdir="$dtiregdir"/split
    dti_native="$dtiregdir"/dti_native$ext
    struct_native="$dtiregdir"/dti_struct_native$ext
    #dtifa_native="$dtiregdir"/dti_FA_native$ext
    #dtimd_native="$dtiregdir"/dti_MD_native$ext
    
    dtifitdir=dti_fit_out
    dtifitbase="$dtifitdir"/dti
    dtifa_native="${dtifitbase}"_FA$ext
    dtimd_native="${dtifitbase}"_MD$ext

    
    
    refinds=( $(tr ' ' '\n' < "$bval" | awk 'NF > 0 && ($1 + 0) == 0 {print NR - 1}') ) || error "refinds calc"
    if [ ${#refinds[@]} -ne 1 ]
    then
        error "dti scan must contain exactly one structural (reference) image"
    fi
    echo "Structural scan found at index $refinds of $dti"
    mkdir "$dtibetdir"
    logcmd dtibetroilog fslroi "$dti" "$dtib0" $refinds 1
    
    
    # BET 
    # https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=ind1807&L=FSL&P=R900&1=FSL&9=A&I=-3&J=on&X=46611749C95967F6DF&Y=stilley%40hollandbloorview.ca&d=No+Match%3BMatch%3BMatches&z=4
    logcmd dtib0betlog bet "$dtib0" "$dtib0betimage" -m
    qcrun fade "DTI b0" "DTI b0 BET" "$dtib0" "$dtib0betimage" "$qcoutdir" --logprefix logs/dtib0betlog

    # Eddy correction
    mkdir "$eddycordir"
    
    # This registers everything to the reference frame using the correlation ratio
    # cost function and a linear transformation (flirt).
    if [ $useeddy -eq 1 ]
    then
        # https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=ind1807&L=FSL&P=R900&1=FSL&9=A&I=-3&J=on&X=46611749C95967F6DF&Y=stilley%40hollandbloorview.ca&d=No+Match%3BMatch%3BMatches&z=4
        logcmd eddycorrectlog eddy_openmp --imain="$dti" --mask="$dtib0betmask" --acqp="$acqp" --index="$index" --bvecs="$bvec" --bvals="$bval" --out="$eddycorbase"
        qcrun logs "Eddy correct (eddy_openmp)" logs/eddycorrectlog "$qcoutdir"
    else
        # logcmd dtibetlog bet "$dti" "$dtibetimage" -m -F
        # qcrun logs "DTI BET (for eddy_correct)" logs/dtibetlog "$qcoutdir"
        logcmd eddycorrectlog eddy_correct "$dti" "$eddycorimage" $refinds
        qcrun logs "Eddy correct (eddy_correct)" logs/eddycorrectlog "$qcoutdir"
        fdt_rotate_bvecs "$bvec" "$bvecrot" "$eddylog"
    fi
    mkdir "$eddycorsplitdir"
    logcmd fslsplitlog fslsplit "$eddycorimage" "$eddycorsplitdir"/ -t
    eddycorb0="$eddycorsplitdir"/$(printf "%04d" $refinds)$ext
    
    mkdir "$dtiregdir"
    dtispacing=$(PrintHeader "$eddycorb0" 1 | tr 'x' ' ')
    logcmd resampleforantslog ResampleImageBySpacing 3 "$nucorcbrain" "$nucorcbrainrs" $dtispacing
    qcrun fade "NU corrected brain" "NU corrected brain dti resolution" "$nucorcbrain" "$nucorcbrainrs" "$qcoutdir" --logprefix logs/resampleforantslog
    logcmd antsreglog antsIntermodalityIntrasubject.sh -d 3 -r "$nucorcbrainrs" -R "$nucorcbrain" -i "$eddycorb0" -t 2 -x "$t1betmaskc" -o "$dti2t1"
    qcrun logs "Ants DTI to T1" logs/antsreglog "$qcoutdir"

    mkdir "$dtiregsplitdir"
    nvols=$(fslnvols "$dti")
    declare -a tojoin
    for ((i=0;i<$nvols;i+=1))
    do
        indfmt=$(printf "%04d" $i)
        inreg="$eddycorsplitdir"/$indfmt$ext
        outreg="$dtiregsplitdir"/$indfmt$ext
        logcmd antsapply${indfmt}log antsApplyTransforms -d 3 -r "$nucorcbrain" -i "$inreg" -t "$dti2t1_warp" -t "$dti2t1_aff" -o "$outreg" -n Linear
        tojoin[$i]="$outreg"
        cat logs/antsapply${indfmt}log_stdout.txt >> logs/antsapplylog_stdout.txt
        cat logs/antsapply${indfmt}log_stderr.txt >> logs/antsapplylog_stderr.txt
    done
    logcmd fslmergelog fslmerge -t "$dti_native" "${tojoin[@]}"
    struct_native="$dtiregsplitdir"/$(printf "%04d" $refinds)$ext
    qcrun fade "T1" "DTI b0 in T1 coords" "$nucorc" "$struct_native" "$qcoutdir" --logprefix logs/antsapplylog

    # DTIFIT
    
    
    mkdir "$dtifitdir"
    
    logcmd dtifitlog dtifit --data="$dti_native" --out="$dtifitbase" --mask="$t1betmaskc" --bvecs="$bvecrot" --bvals="$bval"
    qcrun logs "DTI Fit" logs/dtifitlog "$qcoutdir"
    qcrun static "DTI Fit: FA" "$dtifa_native" "$qcoutdir"
    qcrun static "DTI Fit: MD" "$dtimd_native" "$qcoutdir"
    
    qcrun fade "T1" "MD" "$nucorc" "$dtimd_native" "$qcoutdir"
    qcrun static "Brain mask over FA" "$dtifa_native" "$qcoutdir" --labelfile "$brainmask_native"
    qcrun static "Brain mask over MD" "$dtimd_native" "$qcoutdir" --labelfile "$brainmask_native"
    qcrun static "Lobe mask over FA" "$dtifa_native" "$qcoutdir" --labelfile "$atlas_native"
    qcrun static "Lobe mask over MD" "$dtimd_native" "$qcoutdir" --labelfile "$atlas_native"
    
    # Data extraction
    
    
    printstats "$combined_atlas" "FA" "$dtifa_native" 28 >> "$statsfile" || error "printstats"
    printstats "$combined_atlas" "MD" "$dtimd_native" 28 >> "$statsfile" || error "printstats"
    
    
    printstats "$simple_atlas" "FA" "$dtifa_native" 2 >> "$statsfile_simple" || error "printstats"
    printstats "$simple_atlas" "MD" "$dtimd_native" 2 >> "$statsfile_simple" || error "printstats"

fi

# Cleanup
ERROR=0
WARNING=0
errlogs=$(ls logs/*stderr.txt | grep -v antsreglog)
if cat $errlogs | grep -v -e '^Saving result to .* (type = MINC )\s*\[ ok \]$' > /dev/null
then
    # something was found in stderr
    echo "ERROR. stderr output indicates error" > status.txt
    ERROR=1
else
    echo "stderr output does not indicate error" > status.txt
fi
if [ $(wc -l < logs/antsreglog_stderr.txt) -ne 17 ]
then
    echo "ERROR antsreglog_stderr does not have expected number of lines (17)." >> status.txt
    ERROR=1
else
    echo "antsreglog_stderr has the correct number of lines (17)." >> status.txt
fi
if grep -e '^Warning, Jacobian not within prescribed range' logs/fnirtlog_stdout.txt > /dev/null
then
    WARNING=1
    
    if ! grep -e '^Warning, Jacobian not within prescribed range' logs/fnirtlog_stdout.txt | awk '($(16) < -0.5) {exit 1}'
    then
	ERROR=1
	echo "ERROR. logs/fnirtlog_stdout.txt indicates jacobian determinent is well outside prescribed range. Check registrations" >> status.txt
    else
	echo "WARNING. logs/fnirtlog_stdout.txt indicates a warning with Jacobians. Check registrations" >> status.txt
    fi
else
    echo "logs/fnirtlog_stdout.txt indicates no warnings or errors" >> status.txt
fi
echo $ERROR > errorflag
echo $WARNING > warningflag

popd > /dev/null

exit $ERROR
