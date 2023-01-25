# Set the base image to Ubuntu 16.04 and NVIDIA GPU
FROM tensorflow/tensorflow:latest-gpu

# File Author / Maintainer
MAINTAINER Ryo NIWA

ENV TZ=Asia/Tokyo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && \
    apt-get install --yes wget \
                          apt-transport-https \
                          libzmq5 \
                          libnvidia-compute-470-server \
                          sudo \
                          gzip \
                          pandoc \
                          pandoc-citeproc \
                          xtail \
                          curl \
                          libtiff5 \
                          file \
                          git

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-py39_4.12.0-Linux-x86_64.sh -O ~/Miniconda.sh && \
    mkdir -p /opt && \
    /bin/bash ~/Miniconda.sh -b -p /opt/conda && \
    rm ~/Miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
    /opt/conda/bin/conda clean -afy
ENV PATH $PATH:/opt/conda/bin

RUN conda update -y -n base conda && \
    conda config --add channels defaults && \
    conda config --add channels bioconda && \
    conda config --add channels conda-forge && \
    conda install -y -c conda-forge mamba 

RUN conda create -y -n DAJIN_nanosim python=3.7 
SHELL ["conda", "run", "-n", "DAJIN_nanosim", "/bin/bash", "-c"]    
RUN git clone https://github.com/bcgsc/NanoSim.git && \
    conda install --file NanoSim/requirements.txt -c conda-forge -c bioconda
    
RUN conda create -y -n DAJIN python=3.8 
SHELL ["conda", "run", "-n", "DAJIN", "/bin/bash", "-c"]  

RUN mamba install -c bioconda samtools==1.9 && \
    mamba install -y emboss && \
    mamba install minimap2 && \
    mamba install -y -n DAJIN -c anaconda tensorflow tensorflow-gpu && \
    mamba install -c anaconda numpy && \
    mamba install -y hdbscan && \
    mamba install -y pandas && \
    mamba install -y scikit-learn && \
    mamba install -y joblib 

RUN mamba install -y -c conda-forge r-base && \
    mamba install -y -c conda-forge r-essentials && \
    mamba install -y -c conda-forge r-reticulate && \
    Rscript -e 'install.packages("pacman", repos="https://cloud.r-project.org/")' && \
    Rscript -e 'pacman::p_load("RColorBrewer", "vroom", "furrr", "tidyfast")'

COPY libcrypto.so.1.0.0 /opt/conda/envs/DAJIN_nanosim/lib/libcrypto.so.1.0.0
RUN cp /opt/conda/envs/DAJIN_nanosim/lib/libcrypto.so.1.0.0 /opt/conda/envs/DAJIN/lib/libcrypto.so.1.0.0 && \
    cp /opt/conda/envs/DAJIN_nanosim/lib/libcrypto.so.3 /opt/conda/envs/DAJIN/lib/libcrypto.so.3
    
CMD [ "/bin/bash" ]