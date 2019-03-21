FROM centos:7.6.1810

RUN yum install -y wget file bc
RUN wget --no-verbose https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.0/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
RUN tar -C /opt/ -xzvf freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
RUN sed '1aexport FREESURFER_HOME=/opt/freesurfer' < /opt/freesurfer/SetUpFreeSurfer.sh > /etc/profile.d/freesurfer.sh
RUN wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py
RUN python fslinstaller.py -V 6.0.1 -d /opt/fsl -E
RUN echo "source /etc/profile.d/freesurfer.sh" > /etc/chargeinitstub
RUN echo "source /etc/profile.d/fsl.sh" >> /etc/chargeinitstub
RUN mkdir /root/matlab
RUN touch /root/matlab/startup.m  # to keep the freesurfer initialization quiet

# Remove unneeded files to reduce image size
RUN rm freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz
RUN rm -rf /opt/freesurfer/average
RUN rm -rf /opt/freesurfer/subjects
RUN rm -rf /opt/fsl/bin/FSLeyes
RUN find /opt/fsl/data/standard/ -not -name 'MNI152_T1_2mm*' -exec rm -rf {} +

ENV BASH_ENV="/etc/chargeinitstub"

COPY scripts /opt/charge/scripts
COPY utils /opt/charge/utils
COPY models /opt/charge/models

ENV CHARGEDIR=/opt/charge

ENTRYPOINT ["/bin/bash", "/opt/charge/scripts/pipeline.sh"]
