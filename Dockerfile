FROM ubuntu:17.04

RUN apt-get update && \
    apt-get install --yes \
            build-essential \
            tar \
            git \
            locales \
            ed \
            less \
            vim-tiny \
            ca-certificates \
            wget \
            curl \
            zip \
            unzip \
            rsync && \
    apt-get purge && apt-get clean

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_VER 4.3.21
ENV CONDA_DIR /opt/conda
ENV APP_DIR /srv/app
ENV PATH ${APP_DIR}/venv/bin:$CONDA_DIR/bin:$PATH
ENV SHELL /bin/bash
ENV NB_USER jovyan
ENV NB_UID 1000
ENV HOME /home/$NB_USER
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Create jovyan user with UID=1000 and in the 'users' group
#RUN useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \

RUN adduser --disabled-password --gecos "Default Jupyter user" jovyan && \
    mkdir -p ${APP_DIR}   && chown -R $NB_USER:$NB_USER ${APP_DIR} && \
    mkdir -p ${CONDA_DIR} && chown -R $NB_USER:$NB_USER $CONDA_DIR

USER $NB_USER
WORKDIR $HOME

# Install conda as jovyan
RUN cd /tmp && \
    mkdir -p $CONDA_DIR && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-${CONDA_VER}-Linux-x86_64.sh && \
    echo "e9089c735b4ae53cb1035b1a97cec9febe6decf76868383292af589218304a90 *Miniconda3-${CONDA_VER}-Linux-x86_64.sh" | sha256sum -c - && \
    /bin/bash Miniconda3-${CONDA_VER}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Miniconda3-${CONDA_VER}-Linux-x86_64.sh && \
    $CONDA_DIR/bin/conda config --system --add channels conda-forge && \
    $CONDA_DIR/bin/conda config --system --set auto_update_conda false && \
    conda clean -tipsy

# Install Jupyter Notebook and Hub
RUN conda install --quiet --yes \
    notebook=5.0.0 \
    jupyterhub=0.7.2 \
    ipywidgets=5.2.2 \
    jupyterlab=0.23.2 \
    && conda clean -tipsy


# # Install Jupyter Notebook and Hub
# RUN conda install --quiet --yes \
#     matplotlib==2.0.0 \
#     numpy==1.12.1 \
#     pandas==0.19.2 \
#     scipy==0.19.0 \
#     statsmodels==0.8.0 \
#     && conda clean -tipsy

#RUN python3 -m venv ${APP_DIR}/venv

RUN jupyter nbextension enable --py widgetsnbextension --sys-prefix && \
    jupyter serverextension enable --py jupyterlab --sys-prefix

ADD requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# interact notebook extension
RUN pip install git+https://github.com/data-8/nbpuller.git@8142e3c && \
	jupyter serverextension enable --sys-prefix --py nbpuller && \
	jupyter nbextension install --sys-prefix --py nbpuller && \
	jupyter nbextension enable --sys-prefix --py nbpuller

RUN conda create --quiet --yes -p $CONDA_DIR/envs/python2 python=2.7 \
    'ipython=5.3*' \
    'ipywidgets=5.2.2*' \
    && \
    conda clean -tipsy

# Add shortcuts to distinguish pip for python2 and python3 envs
RUN ln -s $CONDA_DIR/envs/python2/bin/pip $CONDA_DIR/bin/pip2 && \
    ln -s $CONDA_DIR/envs/python2/bin/python2 $CONDA_DIR/bin/python2 && \
    ln -s $CONDA_DIR/envs/python2/bin/python2.7 $CONDA_DIR/bin/python2.7 && \
    ln -s $CONDA_DIR/envs/python2/bin/ipython $CONDA_DIR/bin/ipython2 && \
    ln -s $CONDA_DIR/bin/pip $CONDA_DIR/bin/pip3

USER root

# Install Python 2 kernel spec globally to avoid permission problems when NB_UID
# switching at runtime and to allow the notebook server running out of the root
# environment to find it. Also, activate the python2 environment upon kernel
# launch.
RUN pip install kernda --no-cache && \
    $CONDA_DIR/envs/python2/bin/python -m ipykernel install && \
    kernda -o -y /usr/local/share/jupyter/kernels/python2/kernel.json && \
    pip uninstall kernda -y

#RUN  mkdir -p /srv/app   && chown -R $NB_USER:$NB_USER /srv/app && \
#     python3 -m venv /srv/app/venv

USER $NB_USER

# R packages including IRKernel which gets installed globally.
RUN conda config --system --add channels r && \
    conda install --quiet --yes \
    'rpy2=2.8*' \
    'r-base=3.3.2' \
    'r-irkernel=0.7*' \
    'r-plyr=1.8*' \
    'r-devtools=1.12*' \
    'r-tidyverse=1.0*' \
    'r-shiny=0.14*' \
    'r-rmarkdown=1.2*' \
    'r-forecast=7.3*' \
    'r-rsqlite=1.1*' \
    'r-reshape2=1.4*' \
    'r-nycflights13=0.2*' \
    'r-caret=6.0*' \
    'r-rcurl=1.95*' \
    'r-crayon=1.3*' \
    'r-randomforest=4.6*' && conda clean -tipsy

USER root

ARG RSTUDIO_VERSION
ARG PANDOC_TEMPLATES_VERSION
ENV PANDOC_TEMPLATES_VERSION ${PANDOC_TEMPLATES_VERSION:-1.18}

## Add RStudio binaries to PATH
ENV PATH /usr/lib/rstudio-server/bin:$PATH

## Download and install RStudio server & dependencies
## Attempts to get detect latest version, otherwise falls back to version given in $VER
## Symlink pandoc, pandoc-citeproc so they are available system-wide
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    file \
    git \
    libapparmor1 \
    libcurl4-openssl-dev \
    libedit2 \
    libssl-dev \
    lsb-release \
    psmisc \
    sudo \
    wget \
  && RSTUDIO_LATEST=$(wget --no-check-certificate -qO- https://s3.amazonaws.com/rstudio-server/current.ver) \
  && [ -z "$RSTUDIO_VERSION" ] && RSTUDIO_VERSION=$RSTUDIO_LATEST || true \
  && wget -q http://download2.rstudio.org/rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
  && dpkg -i rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
  && rm rstudio-server-*-amd64.deb

RUN ln -sf /opt/conda/lib/R /usr/lib/R
RUN mkdir -p /usr/share/R/doc

USER $NB_USER

RUN pip install git+https://github.com/jupyterhub/nbserverproxy; \
    jupyter serverextension enable --py nbserverproxy; \
    pip install git+https://github.com/jupyterhub/nbrsessionproxy; \
    jupyter serverextension enable  --py --sys-prefix nbrsessionproxy; \
    jupyter nbextension     install --py --sys-prefix nbrsessionproxy; \
    jupyter nbextension     enable  --py --sys-prefix nbrsessionproxy



# USER root

# ENV R_BASE_VERSION 3.3.2

# ## Now install R and littler, and create a link for littler in /usr/local/bin
# ## Also set a default CRAN repo, and make sure littler knows about it too
# RUN echo 'options(repos = c(CRAN = "https://cran.rstudio.com/"), download.file.method = "libcurl")' >> /etc/R/Rprofile.site \
# 	&& rm -rf /tmp/downloaded_packages/ /tmp/*.rds \
# 	&& rm -rf /var/lib/apt/lists/*

# ARG RSTUDIO_VERSION
# ARG PANDOC_TEMPLATES_VERSION 
# ENV PANDOC_TEMPLATES_VERSION ${PANDOC_TEMPLATES_VERSION:-1.18}

# ## Add RStudio binaries to PATH
# ENV PATH /usr/lib/rstudio-server/bin/:$PATH

# RUN apt-get update \
#   && apt-get install -y --no-install-recommends \
#     file \
#     git \
#     libapparmor1 \
#     libcurl4-openssl-dev libssl1.0.0 \
#     libedit2 \
#     libssl-dev \
#     lsb-release \
#     psmisc \
#     sudo \
#     pandoc \
#     wget \
#   && RSTUDIO_LATEST=$(wget --no-check-certificate -qO- https://s3.amazonaws.com/rstudio-server/current.ver) \
#   && [ -z "$RSTUDIO_VERSION" ] && RSTUDIO_VERSION=$RSTUDIO_LATEST || true \
#   && wget -q http://download2.rstudio.org/rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
#   && dpkg -i rstudio-server-${RSTUDIO_VERSION}-amd64.deb \
#   && rm rstudio-server-*-amd64.deb \
#   ## Symlink pandoc & standard pandoc templates for use system-wide
#   && ln -s /usr/lib/rstudio-server/bin/pandoc/pandoc /usr/local/bin \
#   && ln -s /usr/lib/rstudio-server/bin/pandoc/pandoc-citeproc /usr/local/bin \
#   && wget https://github.com/jgm/pandoc-templates/archive/${PANDOC_TEMPLATES_VERSION}.tar.gz \
#   && mkdir -p /opt/pandoc/templates && tar zxf ${PANDOC_TEMPLATES_VERSION}.tar.gz \
#   && cp -r pandoc-templates*/* /opt/pandoc/templates && rm -rf pandoc-templates* \
#   && mkdir /root/.pandoc && ln -s /opt/pandoc/templates /root/.pandoc/templates \
#   && apt-get clean \
#   && rm -rf /var/lib/apt/lists/ \
#   ## RStudio configuration for docker
#   && mkdir -p /etc/R \
#   && echo '\n\
#     \n# Configure httr to perform out-of-band authentication if HTTR_LOCALHOST \
#     \n# is not set since a redirect to localhost may not work depending upon \
#     \n# where this Docker container is running. \
#     \nif(is.na(Sys.getenv("HTTR_LOCALHOST", unset=NA))) { \
#     \n  options(httr_oob_default = TRUE) \
#     \n}' >> /etc/R/Rprofile.site \
#   && echo "PATH=\"/usr/lib/rstudio-server/bin/:\${PATH}\"" >> /etc/R/Renviron.site \
#   ## Need to configure non-root user for RStudio
#   && useradd rstudio \
#   && echo "rstudio:rstudio" | chpasswd \
# 	&& mkdir /home/rstudio \
# 	&& chown rstudio:rstudio /home/rstudio \
# 	&& addgroup rstudio staff \
#   ## Set up S6 init system
#   && wget -P /tmp/ https://github.com/just-containers/s6-overlay/releases/download/v1.11.0.1/s6-overlay-amd64.tar.gz \
#   && tar xzf /tmp/s6-overlay-amd64.tar.gz -C / \
#   && mkdir -p /etc/services.d/rstudio \
#   && echo '#!/bin/bash \
#            \n exec /usr/lib/rstudio-server/bin/rserver --server-daemonize 0' \
#            > /etc/services.d/rstudio/run \
#    && echo '#!/bin/bash \
#            \n rstudio-server stop' \
#            > /etc/services.d/rstudio/finish \
#   && ls \
#   && apt-get purge && apt-get clean

USER $NB_USER


RUN conda install --quiet --yes \
    matplotlib==2.0.0 \
    numpy==1.12.1 \
    pandas==0.19.2 \
    scipy==0.19.0 \
    statsmodels==0.8.0 \
    'nomkl' \
    'pandas=0.19*' \
    'numexpr=2.6*' \
    'matplotlib=2.0*' \
    'scipy=0.19*' \
    'seaborn=0.7*' \
    'scikit-learn=0.18*' \
    'scikit-image=0.12*' \
    'sympy=1.0*' \
    'cython=0.25*' \
    'patsy=0.4*' \
    'statsmodels=0.8*' \
    'cloudpickle=0.2*' \
    'dill=0.2*' \
    'numba=0.31*' \
    'bokeh=0.12*' \
    'hdf5=1.8.17' \
    'h5py=2.6*' \
    'sqlalchemy=1.1*' \
    'pyzmq' \
    'vincent=0.4.*' \
    'beautifulsoup4=4.5.*' \
    'xlrd' && \
    conda clean -tipsy

RUN conda install --quiet --yes -n python2 \
    matplotlib==2.0.0 \
    numpy==1.12.1 \
    pandas==0.19.2 \
    scipy==0.19.0 \
    statsmodels==0.8.0 \
    'nomkl' \
    'pandas=0.19*' \
    'numexpr=2.6*' \
    'matplotlib=2.0*' \
    'scipy=0.19*' \
    'seaborn=0.7*' \
    'scikit-learn=0.18*' \
    'scikit-image=0.12*' \
    'sympy=1.0*' \
    'cython=0.25*' \
    'patsy=0.4*' \
    'statsmodels=0.8*' \
    'cloudpickle=0.2*' \
    'dill=0.2*' \
    'numba=0.31*' \
    'bokeh=0.12*' \
    'hdf5=1.8.17' \
    'h5py=2.6*' \
    'sqlalchemy=1.1*' \
    'pyzmq' \
    'vincent=0.4.*' \
    'beautifulsoup4=4.5.*' \
    'xlrd' && \
    conda clean -tipsy

EXPOSE 8888
USER $NB_USER

# The desktop package uses /usr/lib/rstudio/bin
ENV PATH="${PATH}:/usr/lib/rstudio-server/bin"
ENV LD_LIBRARY_PATH="/usr/lib/R/lib:/lib:/usr/lib/x86_64-linux-gnu:/usr/lib/jvm/java-7-openjdk-amd64/jre/lib/amd64/server:/opt/conda/lib/R/lib"
