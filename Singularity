Bootstrap: yum
OSVersion: 7
MirrorURL: http://mirror.centos.org/centos-%{OSVERSION}/%{OSVERSION}/os/x86_64/
From: pndni/charge_gm_wm_properties_pipeline

%post
    yum install -y wget file bc
    wget https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.0/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
    tar -C /opt/ -xzvf freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
    sed '1aexport FREESURFER_HOME=/opt/freesurfer' < /opt/freesurfer/SetUpFreeSurfer.sh > /etc/profile.d/freesurfer.sh
    wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py
    python fslinstaller.py -V 6.0.1 -d /opt/fsl -E
    echo "source /etc/profile.d/freesurfer.sh" > /etc/chargeinitstub
    echo "source /etc/profile.d/fsl.sh" >> /etc/chargeinitstub
    mkdir /root/matlab
    touch /root/matlab/startup.m  # to keep the freesurfer initialization quiet
    rm freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
    # Remove unneeded files to make the image smaller
    rm -rf /opt/freesurfer/average
    rm -rf /opt/freesurfer/subjects
    rm -rf /opt/fsl/bin/FSLeyes
    find /opt/fsl/data/standard/ -not -name 'MNI152_T1_2mm*' -exec rm -rf {} +

%environmentment
   BASH_ENV="/etc/chargeinitstub"
   CHARGEDIR=/opt/charge

%files
    scripts /opt/charge/scripts
    utils /opt/charge/utils
    models /opt/charge/models

%runscript
    /bin/bash /opt/charge/scripts/pipeline.sh "$@"