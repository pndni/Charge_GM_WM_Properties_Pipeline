FROM centos:7.6.1810

RUN yum install -y epel-release
RUN yum install -y wget file bc tar gzip libquadmath which bzip2 libgomp tcsh perl zlib zlib-devel hostname
RUN yum groupinstall -y "Development Tools"
RUN wget https://github.com/Kitware/CMake/releases/download/v3.14.0/cmake-3.14.0-Linux-x86_64.sh
RUN mkdir -p /opt/cmake
RUN /bin/bash cmake-3.14.0-Linux-x86_64.sh --prefix=/opt/cmake --skip-license
RUN rm cmake-3.14.0-Linux-x86_64.sh

# ANTs
# it doesn't look like the libraries are needed. no RPATH or
# RUNPATH used. as determined by running
# for i in `ls`; do if [ $(file $i | awk '{print $2}') == "ELF" ]; then objdump -x $i | awk -v FS='\n' -v RS='\n\n' '$1 == "Dynamic Section:" {print}' | grep -i path ; fi; done;
# in /scif/apps/ants/bin
# and the documentation doesn't say to alter LD_LIBRARY_PATH
RUN tmpdir=$(mktemp -d) && \
    pushd $tmpdir && \
    git clone --branch v2.3.1 https://github.com/ANTsX/ANTs.git ANTs_src && \
    mkdir ANTs_build && \
    pushd ANTs_build && \
    /opt/cmake/bin/cmake ../ANTs_src && \
    make -j 2 && \
    popd && \
    mkdir -p /opt/ants/bin && \
    cp ANTs_src/Scripts/* /opt/ants/bin/ && \
    cp ANTs_build/bin/* /opt/ants/bin/ && \
    popd && \
    rm -rf $tmpdir
ENV PATH=/opt/ants/bin:$PATH
ENV ANTSPATH=/opt/ants/bin

# FSL
RUN wget --output-document=/root/fslinstaller.py https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py 
RUN python /root/fslinstaller.py -p -V 6.0.1 -d /opt/fsl
RUN rm /root/fslinstaller.py
ENV FSLDIR=/opt/fsl
ENV FSLOUTPUTTYPE="NIFTI_GZ"
ENV FSLMULTIFILEQUIT="TRUE"
ENV FSLTCLSH=/opt/fsl/bin/fsltclsh
ENV FSLWISH=/opt/fsl/bin/fslwish
ENV FSLLOCKDIR=""
ENV FSLMACHINELIST=""
ENV FSLREMOTECALL=""
ENV FSLGECUDAQ="cuda.q"
ENV PATH=/opt/fsl/bin:$PATH

# FreeSurfer
RUN wget --no-verbose --output-document=/root/freesurfer.tar.gz https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.1/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.1.tar.gz
RUN tar -C /opt -xzvf /root/freesurfer.tar.gz
RUN rm /root/freesurfer.tar.gz
ENV OS="Linux"
ENV FREESURFER_HOME=/opt/freesurfer
ENV FS_OVERRIDE=0
ENV FSFAST_HOME=/opt/freesurfer/fsfast
ENV FUNCTIONALS_DIR=/opt/freesurfer/sessions
ENV MINC_BIN_DIR=/opt/freesurfer/mni/bin
ENV MNI_DIR=/opt/freesurfer/mni
ENV MINC_LIB_DIR=/opt/freesurfer/mni/lib
ENV MNI_DATAPATH=/opt/freesurfer/mni/data
ENV LOCAL_DIR=/opt/freesurfer/local
ENV FSF_OUTPUT_FORMAT="nii.gz"
ENV MNI_PERL5LIB=/opt/freesurfer/mni/share/perl5
ENV PERL5LIB=${MNI_PERL5LIB}:$PERL5LIB
ENV PATH=${MINC_BIN_DIR}:$PATH
ENV PATH=/opt/freesurfer/fsfast/bin:/opt/freesurfer/bin:/opt/freesurfer/tktools:$PATH
ENV FIX_VERTEX_AREA=""

RUN mkdir -p /mnt/indir
RUN mkdir -p /mnt/outdir

ENV CHARGEDIR=/opt/charge
COPY scripts /opt/charge/scripts/
COPY utils /opt/charge/utils/
COPY models /opt/charge/models/
COPY QC /opt/charge/QC/

ENTRYPOINT ["/opt/charge/scripts/pipeline.sh"]

LABEL Maintainer="Steven Tilley"
LABEL Version=1.0.0-alpha12