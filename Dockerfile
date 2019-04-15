FROM centos:7.6.1810

RUN yum install -y wget file bc tar gzip libquadmath which bzip2 libgomp tcsh perl less vim zlib zlib-devel hostname
RUN yum groupinstall -y "Development Tools"

# FREESURFER
RUN wget --no-verbose --output-document=/root/freesurfer.tar.gz https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.1/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.1.tar.gz
RUN tar -C /opt -xzvf /root/freesurfer.tar.gz
RUN rm /root/freesurfer.tar.gz

ENV NO_FSFAST 1
ENV FREESURFER_HOME /opt/freesurfer

# FSL
RUN wget --output-document=/root/fslinstaller.py https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py 
RUN python /root/fslinstaller.py -p -V 6.0.1 -d /opt/fsl
RUN rm /root/fslinstaller.py

ENV FSLDIR /opt/fsl
ENV PATH $FSLDIR/bin:$PATH

# CHARGE PIPELINE
RUN mkdir /opt/charge
COPY scripts /opt/charge/scripts
COPY utils /opt/charge/utils
COPY models /opt/charge/models
COPY QC /opt/charge/QC

# ENVIRONMENT SETUP
ENV CHARGEDIR /opt/charge

ENV FSLOUTPUTTYPE NIFTI_GZ
ENV FSLMULTIFILEQUIT TRUE
ENV FSLTCLSH $FSLDIR/bin/fsltclsh
ENV FSLWISH $FSLDIR/bin/fslwish
ENV FSLLOCKDIR ""
ENV FSLMACHINELIST ""
ENV FSLREMOTECALL ""
ENV FSLGECUDAQ cuda.q

ENV OS Linux
ENV FS_OVERRIDE 0
ENV FSFAST_HOME $FREESURFER_HOME/fsfast
ENV SUBJECTS_DIR $FREESURFER_HOME/subjects
ENV FUNCTIONALS_DIR $FREESURFER_HOME/sessions
ENV MINC_BIN_DIR $FREESURFER_HOME/mni/bin
ENV MNI_DIR $FREESURFER_HOME/mni
ENV MINC_LIB_DIR $FREESURFER_HOME/mni/lib
ENV MNI_DATAPATH $FREESURFER_HOME/mni/data
ENV LOCAL_DIR $FREESURFER_HOME/local
ENV FSF_OUTPUT_FORMAT nii.gz
ENV MNI_PERL5LIB "$FREESURFER_HOME/mni/share/perl5"
ENV PERL5LIB "$MNI_PERL5LIB":"$PERL5LIB"
ENV PATH $MINC_BIN_DIR:$PATH
ENV PATH $FREESURFER_HOME/tktools:$PATH
ENV PATH $FREESURFER_HOME/bin:$FSFAST_HOME/bin:$PATH
ENV FIX_VERTEX_AREA ""

RUN mkdir -p /mnt/outdir
RUN mkdir -p /mnt/indir

LABEL Maintainer="Steven Tilley"
LABEL Version=dev
LABEL FSL_License=https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense
LABEL FSL_Version=6.0.1
LABEL FreeSurfer_License=https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/Licence
LABEL FreeSurfer_Version=6.0.1

ENTRYPOINT ["/opt/charge/scripts/pipeline.sh"]