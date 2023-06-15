
##################################################################
##                           README                             ##
##################################################################
## Este Dockerfile permite montar un entorno de desarrollo con  ##
## RStudio Server y todos los paquetes R necesarios.            ##
##################################################################



###########################
## Set GLOBAL BUILD ARGS ##
###########################


# Set APP HOME
ARG APP_HOME="/opt/smap"

# Set global USERs args
ARG ROOT_PWD="root_passwd"
ARG NON_ROOT_PWD="nonroot"
ARG NON_ROOT_USR="nonroot"
ARG NON_ROOT_UID="1001"  # el usuario rstudio ya tiene el UID 1000
ARG NON_ROOT_GID="1001"  # el grupo rstudio ya tiene el GID 1000



#################################
## Stage 1: Install R packages ##
#################################

# Create image
FROM rocker/rstudio:4.1.2 AS r_builder

# set environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Install OS packages
RUN apt-get -y -qq update && \
    apt-get -y -qq upgrade && \
    apt-get -y -qq --no-install-recommends install \
        build-essential \
        # to install ncdf4 (R)
        libnetcdf-dev \
        # to install sf (R)
        # to install terra, a dependency of raster (R)
        gdal-bin libgdal-dev \
        # to install classInt, a dependency of sf (R)
        gfortran \
        # to install units, a dependency of sf (R)
        libudunits2-dev \
        # to install ragg, a dependency of devtools (R)
        libharfbuzz-dev libfribidi-dev && \
    rm -rf /var/lib/apt/lists/*

# Install R packages
RUN R -e "options(warn=2); install.packages('dplyr', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('here', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('ncdf4', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('raster', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('R6', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('sf', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('sp', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('stringr', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('terra', verbose=T, quiet=T, keep_outputs='/tmp/')"
RUN R -e "options(warn=2); install.packages('BiocManager', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); BiocManager::install('rhdf5', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('smapr', verbose=T, quiet=T, keep_outputs='/tmp/')"
# Paquetes archivados el 2023, ver: https://r-spatial.org/r/2023/05/15/evolution4.html
# OBS: antes de dejar de instalarlos, verificar que no sean utilizados directamente
RUN R -e "options(warn=2); install.packages('rgdal', verbose=T, quiet=T, keep_outputs='/tmp/')" \
 && R -e "options(warn=2); install.packages('rgeos', verbose=T, quiet=T, keep_outputs='/tmp/')"



##############################################
## Stage 2: Copy the R installation folders ##
##############################################

# Create image
FROM rocker/rstudio:4.1.2 AS r_final

# set environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Install OS packages
RUN apt-get -y -qq update && \
    apt-get -y -qq upgrade && \
    apt-get -y -qq --no-install-recommends install \
        # to be able to use ncdf4 (R)
        libnetcdf-dev \
        # to be able to use sf (R)
        # to be able to use raster (R)
        gdal-bin libgdal-dev \
        # to be able to import and use units (R)
        libudunits2-dev && \
    rm -rf /var/lib/apt/lists/*

# Install R packages from r_builder
# https://forums.docker.com/t/using-multi-stage-docker-build-for-slimming-down-images-with-r-dependency/67967
RUN mkdir -p /usr/local/lib/R \
             /usr/local/lib/R/site-library
COPY --from=r_builder /usr/local/bin/R /usr/local/bin/R
COPY --from=r_builder /usr/local/bin/Rscript /usr/local/bin/Rscript
COPY --from=r_builder /usr/local/lib/R /usr/local/lib/R
COPY --from=r_builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
COPY --from=r_builder /tmp /tmp

# Set R libs paths (see: https://stat.ethz.ch/R-manual/R-devel/library/base/html/libPaths.html)
ENV R_LIBS="/usr/local/lib/R/library"
ENV R_LIBS_USER="/usr/local/lib/R/site-library"
ENV R_LIBS_SITE="/usr/local/lib/R/site-library"



###################################
## Stage 3: Create non-root user ##
###################################

# Create image
FROM r_final AS non_root

# Load global USER args
ARG ROOT_PWD
ARG NON_ROOT_PWD
ARG NON_ROOT_USR
ARG NON_ROOT_UID
ARG NON_ROOT_GID

# Install OS packages
RUN apt-get -y -qq update && \
    apt-get -y -qq upgrade && \
    apt-get -y -qq --no-install-recommends install \
        # to run sudo
        sudo && \
    rm -rf /var/lib/apt/lists/*

# Modify root password
RUN echo "root:$ROOT_PWD" | chpasswd

# Create a non-root user, so the container can run as non-root
# OBS: the UID and GID must be the same as the user that own the
# input and the output volumes, so there isn't perms problems!!
# Se recomienda crear usuarios en el contendor de esta manera,
# ver: https://nickjanetakis.com/blog/running-docker-containers-as-a-non-root-user-with-a-custom-uid-and-gid
# Se agregar --no-log-init para prevenir un problema de seguridad,
# ver: https://jtreminio.com/blog/running-docker-containers-as-current-host-user/
RUN groupadd --gid $NON_ROOT_GID $NON_ROOT_USR
RUN useradd --no-log-init --uid $NON_ROOT_UID --gid $NON_ROOT_GID \
    --comment "Non-root User Account" --create-home $NON_ROOT_USR

# Modify the password of non-root user
RUN echo "$NON_ROOT_USR:$NON_ROOT_PWD" | chpasswd

# Add non-root user to sudoers and to adm group
# The adm group was added to allow non-root user to see logs
RUN adduser $NON_ROOT_USR sudo && \
    adduser $NON_ROOT_USR adm



###########################################
## Stage 4: Install management packages  ##
###########################################

# Create image
FROM non_root AS builder

# Set environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Install OS packages
RUN apt-get -y -qq update && \
    apt-get -y -qq upgrade && \
    apt-get -y -qq --no-install-recommends install \
        # to see process with pid 1
        htop \
        # to allow edit files
        vim \
        # to show progress through pipelines
        pv && \
    rm -rf /var/lib/apt/lists/*



#####################################
## Stage 5: Install and setup SMAP ##
#####################################

# Create image
FROM builder AS smap_builder

# Set environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Load APP HOME
ARG APP_HOME

# Install OS packages
RUN apt-get -y -qq update && \
    apt-get -y -qq upgrade && \
    apt-get -y -qq --no-install-recommends install \
        # to clone git repos
        git \
        # to run utils::download.file with method="wget"
        wget && \
    rm -rf /var/lib/apt/lists/*

# Create work directory
RUN mkdir -p ${APP_HOME}

# Copy SMAP source
COPY ./* ${APP_HOME}



#####################################
## Stage 6: Setup final SMAP image ##
#####################################

# Import final image
FROM smap_builder

# Load global USER args
ARG NON_ROOT_USR
ARG NON_ROOT_UID
ARG NON_ROOT_GID

# Change app folders owner and group
RUN chown -R $NON_ROOT_UID:$NON_ROOT_GID ${APP_HOME}

# Set permissions of app files
RUN chmod -R ug+rw,o+r ${APP_HOME}

# Run the S6 Overlay INIT, para entender porque ENTRYPOINT [ "/init" ], ver: 
# https://github.com/just-containers/s6-overlay, aunque rocker/rstudio usa CMD, ver:
# https://github.com/rocker-org/rocker-versioned2/blob/master/dockerfiles/rstudio_4.1.2.Dockerfile
ENTRYPOINT [ "/init" ]

# Access non-root user directory
WORKDIR /home/$NON_ROOT_USR

# Resulta que la imagen rocker/rstudio usa s6-overlay, y como se explica aquí:
# https://github.com/rocker-org/shiny/issues/79#issuecomment-633067470
# el "process supervisor" s6-overlay debe correr como root. Sin embargo
# se modificó la imagen para que rstudio corra siempre como no root
USER root

# AUTHORIZATION
# Al acceder a RStudio se solicita usuario y contraseña, las opciones válidas
# son dos: 1- usuario "rstudio", con la clave que se imprime en el log; y 
# 2- usuario non-root creado y la contraseña definida para ese usuario.


# CONSTRUIR CONTENEDOR
# export DOCKER_BUILDKIT=1
# docker build --pull \
# --tag rstudio-smap:latest \
# --build-arg NON_ROOT_UID=$(id -u dbonhaure) \
# --build-arg NON_ROOT_GID=$(id -g dbonhaure) \
# --file Dockerfile .

# CORRER OPERACIONALMENTE CON CRON
# docker run \
# --name rstudio-smap \
# --volume $(pwd):/opt/smap \
# --publish 127.0.0.1:8787:8787 \
# --restart unless-stopped \
# --detach rstudio-smap:latest

