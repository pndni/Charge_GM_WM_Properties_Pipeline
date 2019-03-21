FROM centos:7.6.1810

RUN yum install -y wget file
RUN wget https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.0/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
RUN wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py
RUN tar -C /opt/ -xzvf freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
RUN sed '1aexport FREESURFER_HOME=/opt/freesurfer' < /opt/freesurfer/SetUpFreeSurfer.sh > /etc/profile.d/freesurfer.sh
RUN python fslinstaller.py -V 6.0.1 -d /opt/fsl -E
RUN echo "source /etc/profile.d/freesurfer.sh" > /initstub
RUN echo "source /etc/profile.d/fsl.sh" >> /initstub
RUN mkdir /root/matlab
RUN touch /root/matlab/startup.m  # to keep the freesurfer initialization quiet
RUN rm freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
RUN yum install -y bc
RUN rm -rf /opt/freesurfer/average
RUN rm -rf /opt/freesurfer/subjects
RUN rm -rf /opt/fsl/bin/FSLeyes
RUN find /opt/fsl/data/standard/ -not -name 'MNI152_T1_2mm*' -exec rm -rf {} +

ENV BASH_ENV="/initstub"

COPY scripts /opt/charge/scripts
COPY utils /opt/charge/utils
COPY models /opt/charge/models

ENV CHARGEDIR=/opt/charge

ENTRYPOINT ["/bin/bash", "/opt/charge/scripts/pipeline.sh"]
