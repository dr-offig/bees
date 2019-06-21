##### bees  #####
FROM rocker/r-ubuntu:18.04

ENV DEBIAN_FRONTEND noninteractive
ENV LANG C.UTF-8

# rstudio
RUN apt-get update && apt-get install -y \
            build-essential \
            bzip2 \
            cmake \
            gpg-agent \
            git \
            libtool \
            libc6 \
            libc6-dev \
            nasm \
            unzip \
            wget \
            yasm \
            libnuma1 \
            libnuma-dev \
    && apt-key adv \
       --keyserver keyserver.ubuntu.com \
       --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 \
    && echo "deb https://cloud.r-project.org/bin/linux/ubuntu bionic-cran35/" >> /etc/apt/sources.list \
    && apt-get update && apt-get install -y gdebi-core \
    && wget https://download2.rstudio.org/server/bionic/amd64/rstudio-server-1.2.1335-amd64.deb \
    && gdebi -n rstudio-server-1.2.1335-amd64.deb \
    && useradd bees \
    && echo "bees:bees" | chpasswd \
	  && mkdir /home/bees \
	  && chown bees:bees /home/bees \
	  && addgroup bees staff

# CUDA toolkit (requires NVidia GPU and drivers on host machine) 
RUN apt-get install -y linux-headers-$(uname -r) \
    && wget http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-repo-ubuntu1804_10.1.168-1_amd64.deb \
    && dpkg -i cuda-repo-ubuntu1804_10.1.168-1_amd64.deb \
    && apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub \
    && apt-get update \
    && apt-get install -y cuda \
    && export PATH=/usr/local/cuda-10.1/bin:/usr/local/cuda-10.1/NsightCompute-2019.1${PATH:+:${PATH}} \
    && git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git \
    && cd nv-codec-headers && make && make install && cd ..

# ffmpeg
RUN git clone https://git.ffmpeg.org/ffmpeg.git && cd ffmpeg \
    && ./configure --enable-cuda --enable-cuvid --enable-nvenc --enable-nonfree --enable-libnpp --extra-cflags=-I/usr/local/cuda/include --extra-ldflags=-L/usr/local/cuda/lib64 \
    && make -j 8 && make install

# CUDA aware libraries
RUN apt-get update && apt-get -y --no-install-recommends install \
    g++ \
    freeglut3-dev \
    libx11-dev \
    libxmu-dev \
    libxi-dev \
    libglu1-mesa \
    libglu1-mesa-dev 

# R Tidyverse
RUN apt-get update -qq && apt-get -y --no-install-recommends install \
       libssl-dev \
       libcurl4-openssl-dev \
       libxml2-dev \
       libcairo2-dev \
       libsqlite3-dev \
       libmariadbd-dev \
       libmariadb-client-lgpl-dev \
       libpq-dev \
       libssh2-1-dev \
       unixodbc-dev \
       libsasl2-dev \
    && install2.r --error \
       --deps TRUE \
       httr \
       rvest \
       tidyverse \
       dplyr \
       devtools \
       formatR \
       remotes \
       selectr \
       caTools

RUN mkdir -p /home/bees/portal


#### Extra rstudio stuff ####
## Prevent rstudio from deciding to use /usr/bin/R if a user apt-get installs a package
#RUN  echo 'rsession-which-r=/usr/local/bin/R' >> /etc/rstudio/rserver.conf \
  ## use more robust file locking to avoid errors when using shared volumes:
RUN echo 'lock-type=advisory' >> /etc/rstudio/file-locks \
    && git config --system credential.helper 'cache --timeout=3600' \
    && git config --system push.default simple

## Set up S6 init system
ADD https://github.com/just-containers/s6-overlay/releases/download/v1.21.8.0/s6-overlay-amd64.tar.gz /tmp/

RUN tar xzf /tmp/s6-overlay-amd64.tar.gz -C / \
  && mkdir -p /etc/services.d/rstudio \
  && echo '#!/usr/bin/with-contenv bash\nfor line in $( cat /etc/environment ) ; do export $line ; done\nexec /usr/lib/rstudio-server/bin/rserver --server-daemonize 0' > /etc/services.d/rstudio/run \
  && echo '#!/bin/bash \nrstudio-server stop' > /etc/services.d/rstudio/finish \
  && mkdir -p /home/bees/.rstudio/monitored/user-settings \
  && echo 'alwaysSaveHistory="0"\nloadRData="0"\nsaveAction="0"' > /home/bees/.rstudio/monitored/user-settings/user-settings \
  && chown -R bees:bees /home/bees/.rstudio

## geospatial libraries
RUN apt-get update && apt-get -y --no-install-recommends install \
    libgsl-dev \
    libopenmpi-dev \
    libzmq3-dev \
    lbzip2 \
    libfftw3-dev \
    libgeos-dev \
    libhdf4-alt-dev \
    libhdf5-dev \
    libjq-dev \
    liblwgeom-dev \
    libpq-dev \
    libprotobuf-dev \
    libnetcdf-dev \
    libsqlite3-dev \
    libssl-dev \
    libudunits2-dev \
    netcdf-bin \
    postgis \
    protobuf-compiler \
    sqlite3 \
    tk-dev \
    unixodbc-dev

ENV PROJ_VERSION=6.0.0
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

RUN wget http://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz \
  && tar zxf proj-*tar.gz \
  && cd proj-${PROJ_VERSION} \
  && ./configure \
  && make \
  && make install \
  && cd .. \
  && ldconfig \
  && rm -rf proj*

# install proj-datumgrid:
RUN cd /usr/local/share/proj \
  && wget http://download.osgeo.org/proj/proj-datumgrid-1.8.zip \
  && unzip -o proj-datumgrid*zip \
  && rm proj-datumgrid*zip


# GDAL:
ENV GDAL_VERSION=2.4.1
ENV GDAL_VERSION_NAME=2.4.1

RUN wget http://download.osgeo.org/gdal/${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz \
  && tar zxf gdal-${GDAL_VERSION}.tar.gz \
  && cd gdal-${GDAL_VERSION} \
  && ./configure \
  && make && make install \
  && cd .. \
  && ldconfig \
  && rm -rf gdal*

RUN install2.r --error \
    --deps TRUE \
    raster \
    rgdal

# Some more C libraries
RUN apt-get update && apt-get -y --no-install-recommends install \
    libmagick++-dev

# R packages from github
RUN R -e "devtools::install_github('dr-offig/listenR')"

# user configuration
COPY userconf.sh /etc/cont-init.d/userconf

## running with "-e ADD=shiny" adds shiny server
COPY add_shiny.sh /etc/cont-init.d/add
COPY disable_auth_rserver.conf /etc/rstudio/disable_auth_rserver.conf
COPY pam-helper.sh /usr/lib/rstudio-server/bin/pam-helper
RUN echo "PS1='🐳\[\033[1;36m\]\h:\[\033[1;34m\]\W\[\033[0;35m\]\[\033[1;36m\]> \[\033[0m\]'" >> /root/.bashrc

#### JupyterHub ###
# install Python + NodeJS with conda
WORKDIR /root
RUN wget -q https://repo.continuum.io/miniconda/Miniconda3-4.5.11-Linux-x86_64.sh -O /tmp/miniconda.sh  && \
    echo 'e1045ee415162f944b6aebfe560b8fee */tmp/miniconda.sh' | md5sum -c - && \
    bash /tmp/miniconda.sh -f -b -p /opt/conda && \
    /opt/conda/bin/conda install --yes -c conda-forge \
      python=3.6 sqlalchemy tornado jinja2 traitlets requests pip pycurl \
      nodejs configurable-http-proxy && \
    /opt/conda/bin/pip install --upgrade pip && \
    rm /tmp/miniconda.sh
ENV PATH=/opt/conda/bin:$PATH

RUN conda install -y -c conda-forge jupyterhub && \
    conda install -y notebook  && \
    conda install -y -c conda-forge jupyterlab && \
    jupyter labextension install @jupyterlab/hub-extension

RUN mkdir -p /srv/jupyterhub/
WORKDIR /srv/jupyterhub/
COPY jupyterhub_config.py /srv/jupyterhub/jupyterhub_config.py
EXPOSE 8000

LABEL org.jupyter.service="jupyterhub"

RUN R -e "devtools::install_github('IRkernel/IRkernel'); IRkernel::installspec(prefix='/home/bees/.local')" \
    && chown -R bees:bees /home/bees/.local

RUN pip install ffmpeg-python flask

#ARG SHARE_GID=1001
#ARG PASSWORD=jupyter
# RUN useradd jupyter \
#     && echo "jupyter:jupyter" | chpasswd \
# 	  && mkdir /home/jupyter \
# 	  && chown jupyter:jupyter /home/jupyter \
# 	  && addgroup jupyter staff

# COPY jupyter_userconf.sh /etc/cont-init.d/jupyter_userconf
#RUN mkdir -p /home/bees/portal/notebooks \
#    && chown bees:bees /home/bees/portal/notebooks

## GPU forwarding ##
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,video,utility

# user environment variables
ENV PATH="${PATH}:/home/bees/.local/bin"

#RUN usermod -a -G ${SHARE_GID} bees
ENTRYPOINT ["/init"]
CMD ["jupyterhub"]