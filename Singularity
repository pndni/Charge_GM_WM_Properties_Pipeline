Bootstrap: shub
From: pndni/FSL-and-freesurfer:fsl-6.0.1_freesurfer-6.0.1_1.0.1

%post
    yum install -y epel-release
    yum install -y python36 python36-pip python36-devel python36-virtualenv
    virtualenv-3.6 /opt/reprozip
    source /opt/reprozip/bin/activate
    pip install reprozip
    deactivate


%appfiles charge
    scripts
    utils
    models
    QC

%appenv charge
    source $SCIF_APPENV_all
    CHARGEDIR=$SCIF_APPROOT_charge
    export CHARGEDIR

%appenv trace
    source $SCIF_APPENV_charge
    source /opt/reprozip/bin/activate

%apprun trace
    reprozip trace /bin/bash $CHARGEDIR/scripts/pipeline.sh "$@"

%apprun charge
    /bin/bash $CHARGEDIR/scripts/pipeline.sh "$@"

%labels
    Maintainer Steven Tilley
    
