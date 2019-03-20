#!/bin/bash
set -e  # exit on error
set -u  # exit on undefined variable
\unalias -a  # remove all aliases (e.g. some systems alias 'cp' to 'cp -i')



# Allow signal trapping from subshells so errors can propogte upwards. Trap logic from
# https://stackoverflow.com/questions/9893667/is-there-a-way-to-write-a-bash-function-which-aborts-the-whole-execution-no-mat
# Define Error function that writes message to stderr and exits with optional
# error code (default 1). Also define some error codes. 

trap 'exit 1' TERM
export TOP_PID=$$

error_generic=1
error_nargs=2
error_outdirexists=3
error_fslouttype=4
error_stats=5
error_statsnout=6
error_atlas=7
error_dtiref=8
error_filesnotfound=9

error() {
  exitcode=${2:-$error_generic}
  >&2 echo $1
  kill -s TERM $TOP_PID
}



# Calculate and store hash of this file for logging and reproducibility

selfhash=$(sha256sum $0)



# Either accept 3 arguments (T1 only) or 6 (T1 and DTI)

if [ $# != 3 ] && [ $# != 6 ]
then
    error "number or arguments must be 3 or 6" $error_nargs
fi
indir=$1
t1=$2
outdir=$3
rundti=
if [ $# == 6 ];
then
    rundti=1
    dti=$4
    bvec=$5
    bval=$6
fi

if [ -d "$outdir" ]
then
    error "Output director already exists. Aborting" $error_outdirexists
fi

startdir=$PWD
mkdir $outdir
pushd $outdir > /dev/null

# Chargedir is the root directory of the pipeline files
# If it's not set, assume it is startdir
if [ -z "$CHARGEDIR" ]
then
    $CHARGEDIR=$startdir
fi

if [ ! -e $CHARGEDIR/utils ] || [ ! -e $CHARGEDIR/models ]
then
    exit "utils or models not found. Try setting CHARGEDIR to the root directory of the pipeline repository" $error_filesnotfound
fi

# Check FSLOUTPUTTYPE and store appropriate extension in "ext"

case $FSLOUTPUTTYPE in
    NIFTI_GZ)
	ext=".nii.gz"
	;;
    NIFTI)
	ext=".nii"
	;;
    *)
	error "Unsupported value for FSLOUTPUTTYPE: $FSLOUTPUTTYPE . Aborting" $error_fslouttype
	;;
esac

# T1
#   This portion of the script calculates mean intensity values from a T1 image
#   for each lobe and tissue type (gm/wm). The steps are
#   1. brain extraction with bet
#   2. tissue classification and intensity normalization with FAST
#   3. registering image to MNI152 reference
#   4. transforming lobe and cranium masks from MNI152 space to native space
#   5. using the transformed lobe information and tissue classifications
#      to calculate mean intensity in each region (using the brain extracted image
#      and the normalized image)
#   6. Using the cranium mask to calculate the mean intensity in the cranium for normalization




# Copy input files


cp $indir/$t1 ./

atlas=$CHARGEDIR/models/atlas_labels_ref.nii.gz
icvmask=$CHARGEDIR/models/icbm_mask_ref.nii.gz

#included with FSL
mnirefbrain=${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii
mniref=${FSLDIR}/data/standard/MNI152_T1_2mm.nii
fnirtconf=${FSLDIR}/etc/flirtsch/T1_2_MNI152_2mm.cnf

csf=0
gm=1
wm=2

t1betdir=$outdir/t1_bet_out
t1betimage=$t1betdir/bet$ext

t1fastdir=$outdir/t1_fast_out
t1fastout=$t1fastdir/t1
t1betcor=${t1fastout}_restore$ext
gmmask=${t1fastout}_seg_$gm$ext
wmmask=${t1fastout}_seg_$wm$ext
gmpve=${t1fastout}_pve_$gm$ext
wmpve=${t1fastout}_pve_$wm$ext
gmmask2=${t1fastout}_seg_${gm}_pv$ext
wmmask2=${t1fastout}_seg_${wm}_pv$ext

t1regdir=$outdir/t1_reg_out
s2raff=$t1regdir/struct2mni_affine.mat # affine matrix from the T1 image to the MNI reference
s2rwarp=$t1regdir/struct2mni_warp$ext # warp transformation from the T1 image to the MNI reference
r2swarp=$t1regdir/mni2struct_warp$ext # warp transformation from the MNI reference to the T1 image
t1betcorref=$t1regdir/t1_bet_cor_ref$ext # betcor transformed to MNI coords
atlas_native=$t1regdir/atlas_labels_native$ext
icvmask_native=$t1regdir/icbm_mask_native$ext

nuoutdir=$outdir/t1_nucor_out
nucor=$nuoutdir/nu$ext

statsdir=$outdir/stats_out
statsfile=$statsdir/stats.txt
statsfile_simple=$statsdir/stats_simple.txt
#statsfile2=$statsdir/stats_wmprobmap.txt
gm_atlas=$statsdir/gm_atlas$ext
wm_atlas=$statsdir/wm_atlas$ext
gm_atlas2=$statsdir/gm_atlas_pv$ext
wm_atlas2=$statsdir/wm_atlas_pv$ext
combined_atlas=$statsdir/combined_atlas$ext
combined_atlas2=$statsdir/combined_atlas_pv$ext
atlas_lobe_gm=$statsdir/atlas_lobe_gm$ext
atlas_lobe_wm=$statsdir/atlas_lobe_wm$ext
atlas_lobe_gm2=$statsdir/atlas_lobe_gm_pv$ext
atlas_lobe_wm2=$statsdir/atlas_lobe_wm_pv$ext
simple_atlas=$statsdir/atlas_simple$ext
simple_atlas2=$statsdir/atlas_simple_pv$ext
#nucor_wmweighted=$statsdir/nu_wmweighted$ext
#t1_wmweighted=$statsdir/t1_wmweighted$ext

# Options


t1bet_f=0.4  # parameter passed to FSL's  bet
t1tissuefrac=0.9  # the fraction a voxel must be of a given tissue type to be included in that tissue's mask (for the pv masks)

# BET
#    Extract the brain from the image


# Do bet
mkdir $t1betdir
echo "Running: bet $t1 $t1betimage -f $t1bet_f -R"
bet $t1 $t1betimage -f $t1bet_f -R

# Segmentation
#    Segment into white and grey matter. Simultaneously perform bias
#    field correction


mkdir $t1fastdir
echo "Running: fast --verbose --out=$t1fastout -b -B --segments $t1betimage"
fast --verbose --out=$t1fastout -B --segments $t1betimage

# Registration
#    Reference is MNI152 2mm standard
  

mkdir $t1regdir

# linear registration
#     register to ``brain only'' reference using the bet/bias corrected image (12 DOF)


echo "flirt -ref $mnirefbrain -in $t1betcor -omat $s2raff"
flirt -ref $mnirefbrain -in $t1betcor -omat $s2raff

# nonlinear registration
#     of original image to reference image
#     estimates bias field and nonlinear intensity mapping between images
#     Uses linear registration as initial transformation


echo "fnirt --in=$t1 --config=$fnirtconf --aff=$s2raff --cout=$s2rwarp"
fnirt --in=$t1 --config=$fnirtconf --aff=$s2raff --cout=$s2rwarp

# Transform the bet image to the standard for QC


echo "applywarp --ref=$mniref --in=$t1betcor --out=$t1betcorref --warp=$s2rwarp"
applywarp --ref=$mniref --in=$t1betcor --out=$t1betcorref --warp=$s2rwarp

# Calculate inverse transformation

echo "invwarp --ref=$t1 --warp=$s2rwarp --out=$r2swarp"
invwarp --ref=$t1 --warp=$s2rwarp --out=$r2swarp

# apply inverse transformation to labels and headmask
#    use nearest neighbor interpolation


echo "applywarp --ref=$t1 --in=$atlas --out=$atlas_native --warp=$r2swarp --interp=nn --datatype=int"
applywarp --ref=$t1 --in=$atlas --out=$atlas_native --warp=$r2swarp --interp=nn --datatype=int
echo "applywarp --ref=$t1 --in=$icvmask --out=$icvmask_native --warp=$r2swarp --interp=nn --datatype=int"
applywarp --ref=$t1 --in=$icvmask --out=$icvmask_native --warp=$r2swarp --interp=nn --datatype=int
#applywarp --ref=$t1 --in=$wmprobmap --out=$wmprobmap_native --warp=$r2swarp --interp=nn



# Sanity check

read atlas_min atlas_max <<< $(fslstats $atlas_native -R)
if [[ ! "$atlas_min" =~ ^0\.0*$ ]]
then
   error "Error with atlas label file. Aborting" $error_atlas
fi
if [[ ! "$atlas_max" =~ ^14\.0*$ ]];
then
   error "Error with atlas label file. Aborting" $error_atlas
fi

# MINC intensity correction


mkdir $nuoutdir
echo "mri_nu_correct.mni --i $t1 --o $nucor"
mri_nu_correct.mni --i $t1 --o $nucor

# Calculate intensity values


mkdir $statsdir



# Construct combined atlas by offsetting wm values by 14

fslmaths $atlas_native -mas $gmmask $gm_atlas
fslmaths $atlas_native -add 14 -mas $wmmask -mas $atlas_native $wm_atlas
fslmaths $gm_atlas -add $wm_atlas $combined_atlas



# Constract atlas using more conservative tissue masks. Specifically only voxels with $T1TISSUEFRAC of the tissue

fslmaths $gmpve -thr $t1tissuefrac -bin $gmmask2
fslmaths $wmpve -thr $t1tissuefrac -bin $wmmask2
fslmaths $atlas_native -mas $gmmask2 $gm_atlas2
fslmaths $atlas_native -add 14 -mas $wmmask2 -mas $atlas_native $wm_atlas2
fslmaths $gm_atlas2 -add $wm_atlas2 $combined_atlas2



# Construct atlases combining front, parietal, occipital, and temporal lobes from both hemispheres

fslmaths $combined_atlas -uthr 8.5 -bin $atlas_lobe_gm
fslmaths $combined_atlas -thr 14.5 -uthr 22.5 -bin -mul 2 $atlas_lobe_wm
fslmaths $atlas_lobe_gm -add $atlas_lobe_wm $simple_atlas

fslmaths $combined_atlas2 -uthr 8.5 -bin $atlas_lobe_gm2
fslmaths $combined_atlas2 -thr 14.5 -uthr 22.5 -bin -mul 2 $atlas_lobe_wm2
fslmaths $atlas_lobe_gm2 -add $atlas_lobe_wm2 $simple_atlas2





# Actually calculate stats


label_names=( Frontal_r_gm Parietal_r_gm Temporal_r_gm Occipital_r_gm Frontal_l_gm Parietal_l_gm Temporal_l_gm Occipital_l_gm Cerebellum_l_gm Sub-cortical_l_gm Brainstem_l_gm Cerebellum_r_gm Sub-cortical_r_gm Brainstem_r_gm Frontal_r_wm Parietal_r_wm Temporal_r_wm Occipital_r_wm Frontal_l_wm Parietal_l_wm Temporal_l_wm Occipital_l_wm Cerebellum_l_wm Sub-cortical_l_wm Brainstem_l_wm Cerebellum_r_wm Sub-cortical_r_wm Brainstem_r_wm )
label_names_simple=( gm wm )

statswrapper () {
    local out=
    if [ $3 == "--skew" ] || [ $3 == "--kurtosis" ] || [ $3 == "--median" ]
    then
	out=( $(fslpython $CHARGEDIR/utils/stats.py -K $1 $2 $3) ) || error "pystatserror" $error_stats
    else
	out=( $(fslstats -K $1 $2 $3) ) || error "fslstatserror" $error_stats
    fi
    [ ${#out[*]} == $4 ] || error "unexpected number of outputs" $error_statsnout
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
    local atlasname=$1
    local atlas=$2
    local imagename=$3
    local image=$4
    local nlabels=$5
    # mean
    echo -en "${imagename}_${atlasname}_mean"
    echotsv "$(statswrapper $atlas $image -m $nlabels)"
    echo -e "\t"$(statswrapper $icvmask_native $image -m 1)

    # median
    echo -en "${imagename}_${atlasname}_median"
    echotsv "$(statswrapper $atlas $image --median $nlabels)"
    echo -e "\t"$(statswrapper $icvmask_native $image --median 1)

    # std
    echo -en "${imagename}_${atlasname}_std"
    echotsv "$(statswrapper $atlas $image -s $nlabels)"
    echo -e "\t"$(statswrapper $icvmask_native $image -s 1)

    # range
    local rangetmp=$(statswrapper $atlas $image -R $((nlabels * 2)))
    local rangeicvtmp=( $(statswrapper $icvmask_native $image -R 2) )
    echo -en "${imagename}_${atlasname}_min"
    echotsv "$rangetmp" 0 2
    echo -e "\t"${rangeicvtmp[0]}
    echo -en "${imagename}_${atlasname}_max"
    echotsv "$rangetmp" 1 2
    echo -e "\t"${rangeicvtmp[1]}

    # volume
    local voltmp=$(statswrapper $atlas $image -v $((nlabels * 2)))
    local volicvtmp=( $(statswrapper $icvmask_native $image -v 2) )
    echo -en "${imagename}_${atlasname}_nvoxels"
    echotsv "$voltmp" 0 2
    echo -e "\t"${volicvtmp[0]}
    echo -en "${imagename}_${atlasname}_volume"
    echotsv "$voltmp" 1 2
    echo -e "\t"${volicvtmp[1]}

    # skew
    echo -en "${imagename}_${atlasname}_skew"
    echotsv "$(statswrapper $atlas $image --skew $nlabels)"
    echo -e "\t"$(statswrapper $icvmask_native $image --skew 1)

    # kurtosis
    echo -en "${imagename}_${atlasname}_kurtosis"
    echotsv "$(statswrapper $atlas $image --kurtosis $nlabels)"
    echo -e "\t"$(statswrapper $icvmask_native $image --kurtosis 1)
}

echo "# Data calculated using $(basename $0) with sha256 has ${selfhash}" > $statsfile
echo "# Input directory: $indir"                                          >> $statsfile
echo "# T1 filename: $t1"                                                 >> $statsfile
echo "# DTI filename: $dti"                                               >> $statsfile
echo "# bvec: $bvec"                                                      >> $statsfile
echo "# bval: $bval"                                                      >> $statsfile
echo "# Onput directory: $outdir"                                         >> $statsfile
echo "# $(date)"                                                          >> $statsfile
echotsv "${label_names[*]}"                                               >> $statsfile
echo -e "\tIC"                                                            >> $statsfile

printstats "fullatlas" $combined_atlas "cor" $nucor 28 >> $statsfile
printstats "fullatlas" $combined_atlas "nocor" $t1 28 >> $statsfile
printstats "pvatlas" $combined_atlas2 "cor" $nucor 28 >> $statsfile
printstats "pvatlas" $combined_atlas2 "nocor" $t1 28 >> $statsfile

echo "# Data calculated using $(basename $0) with sha256 has ${selfhash}" > $statsfile_simple
echo "# Input directory: $indir"                                          >> $statsfile_simple
echo "# T1 filename: $t1"                                                 >> $statsfile_simple
echo "# DTI filename: $dti"                                               >> $statsfile_simple
echo "# bvec: $bvec"                                                      >> $statsfile_simple
echo "# bval: $bval"                                                      >> $statsfile_simple
echo "# Onput directory: $outdir"                                         >> $statsfile_simple
echo "# $(date)"                                                          >> $statsfile_simple
echotsv "${label_names_simple[*]}"                                        >> $statsfile_simple
echo -e "\tIC"                                                            >> $statsfile_simple

printstats "fullatlas" $simple_atlas "cor" $nucor 2 >> $statsfile_simple
printstats "fullatlas" $simple_atlas "nocor" $t1 2 >> $statsfile_simple
printstats "pvatlas" $simple_atlas2 "cor" $nucor 2 >> $statsfile_simple
printstats "pvatlas" $simple_atlas2 "nocor" $t1 2 >> $statsfile_simple

# DTI

# adapted from psmd.sh



# Setup


if [ -z "$rundti" ]
then
    exit 0
fi

# Copy input files


\cp $indir/$dti ./
\cp $indir/$bvec ./
\cp $indir/$bval ./

# Create variables

dtibetdir=$outdir/dti_bet_out
dtibetimage=$dtibetdir/bet$ext
dtibetmask=$dtibetdir/bet_mask$ext

eddycordir=$outdir/dti_eddy_out
eddycorimage=$eddycordir/eddycor

dtifitdir=$outdir/dti_fit_out
dtifitbase=$dtifitdir/dti
dtifa=${dtifitbase}_FA$ext
dtimd=${dtifitbase}_MD$ext

dtiregdir=$outdir/dti_reg_out
structforreg=$dtiregdir/dti_struct_for_reg$ext
dti2t1=$dtiregdir/dti2struct_affine.mat
struct_native=$dtiregdir/dti_struct_native$ext
dtifa_native=$dtiregdir/dt1_FA_native$ext
dtimd_native=$dtiregdir/dt1_MD_native$ext

# Eddy correction

mkdir $eddycordir



# #+RESULTS:

# This registers everything to the reference frame using the correlation ratio
# cost function and a linear transformation (flirt). The structural image is found
# by looking for 0 in the bval file.



refinds=( $(tr ' ' '\n' < $bval | awk 'NF > 0 && ($1 + 0) == 0 {print NR - 1}') )
if [ ${#refinds[@]} -ne 1 ]
then
    exit "dti scan must contain exactly one structural (reference) image" error_dtiref
fi
echo "Structural scan found at index $refinds of $dti"
echo "eddy_correct $dti $eddycorimage $refinds"
eddy_correct $dti $eddycorimage $refinds

# BET 

mkdir $dtibetdir



# #+RESULTS:


echo "bet $eddycorimage $dtibetimage -m -F"
bet $eddycorimage $dtibetimage -m -F

# DTIFIT


mkdir $dtifitdir

echo "dtifit --data=$dtibetimage --out=$dtifitbase --mask=$dtibetmask --bvecs=$bvec --bvals=$bval"
dtifit --data=$dtibetimage --out=$dtifitbase --mask=$dtibetmask --bvecs=$bvec --bvals=$bval

# Registration


mkdir $dtiregdir

echo "fslroi $dtibetimage $structforreg $refinds 1"
fslroi $dtibetimage $structforreg $refinds 1
echo "flirt -ref $t1betcor -in $structforreg -omat $dti2t1"
flirt -ref $t1betcor -in $structforreg -omat $dti2t1 -out $struct_native
echo "flirt -ref $t1betcor -init $dti2t1 -applyxfm -in $dtifa -out $dtifa_native"
flirt -ref $t1betcor -init $dti2t1 -applyxfm -in $dtifa -out $dtifa_native
echo "flirt -ref $t1betcor -init $dti2t1 -applyxfm -in $dtimd -out $dtimd_native"
flirt -ref $t1betcor -init $dti2t1 -applyxfm -in $dtimd -out $dtimd_native

# Data extraction


printstats "fullatlas" $combined_atlas "FA" $dtifa_native 28 >> $statsfile
printstats "fullatlas" $combined_atlas "MD" $dtimd_native 28 >> $statsfile
printstats "pvatlas" $combined_atlas2 "FA" $dtifa_native 28 >> $statsfile
printstats "pvatlas" $combined_atlas2 "MD" $dtimd_native 28 >> $statsfile


printstats "fullatlas" $simple_atlas "FA" $dtifa_native 2 >> $statsfile_simple
printstats "fullatlas" $simple_atlas "MD" $dtimd_native 2 >> $statsfile_simple
printstats "pvatlas" $simple_atlas2 "FA" $dtifa_native 2 >> $statsfile_simple
printstats "pvatlas" $simple_atlas2 "MD" $dtimd_native 2 >> $statsfile_simple

# Cleanup

popd > /dev/null
