# ARGUMENTS --------------------------------------------------------------------
##
# Board architecture
##
ARG IMAGE_ARCH=

##
# Base container version
##
ARG BASE_VERSION=3-bookworm

##
# Directory of the application inside container
##
ARG APP_ROOT=

#FROM --platform=linux/${IMAGE_ARCH} \
#    torizon/debian:${BASE_VERSION} AS Deploy

FROM --platform=linux/${IMAGE_ARCH} \
    python:3.9-slim-bookworm AS Build

ARG IMAGE_ARCH
ARG APP_ROOT

# your regular RUN statements here
# Install required packages
RUN apt-get -q -y update && \
    apt-get -q -y install \
    python3 \
    python3-pip \
    python3-venv \
# DO NOT REMOVE THIS LABEL: this is used for VS Code automation
    # __torizon_packages_prod_start__
    # __torizon_packages_prod_end__
# DO NOT REMOVE THIS LABEL: this is used for VS Code automation
    && apt-get clean && apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*

# Create virtualenv
RUN python3 -m venv --copies ${APP_ROOT}/.venv

# Install pip packages on venv
COPY requirements-release.txt /requirements-release.txt
RUN . ${APP_ROOT}/.venv/bin/activate && \
    pip install  -v -r requirements-release.txt && \
    rm requirements-release.txt 


FROM --platform=linux/${IMAGE_ARCH} \
    torizon/debian:3-bookworm AS Middle

## Install Python
RUN apt-get -y update && apt-get install -y \
  python3 python3-dev python3-numpy python3-pybind11 \
  && apt-get clean && apt-get autoremove && rm -rf /var/lib/apt/lists/*

## Install Pip and Wheel ##
RUN apt-get -y update && apt-get install -y \
  python3-pip python3-setuptools python3-wheel \
  && apt-get clean && apt-get autoremove && rm -rf /var/lib/apt/lists/*

## Install Build tools
RUN apt-get -y update && apt-get install -y \
  cmake build-essential gcc g++ git wget unzip patchelf imx-gpu-viv-wayland-dev \
  && apt-get clean && apt-get autoremove && rm -rf /var/lib/apt/lists/*

COPY global_variables.sh global_variables.sh
COPY CMakeLists.txt /tmp/

## Build nn-imx
COPY nn-imx_1.3.0.sh nn-imx_1.3.0.sh
RUN ./nn-imx_1.3.0.sh

## Build tim vx
COPY tim-vx.sh tim-vx.sh
RUN ./tim-vx.sh

## Build tensorflow lite
COPY tensorflow-lite_2.9.1.sh tensorflow-lite_2.9.1.sh
RUN ./tensorflow-lite_2.9.1.sh

## Build tflite vx delegate
COPY tflite-vx-delegate.sh tflite-vx-delegate.sh
RUN ./tflite-vx-delegate.sh


FROM --platform=linux/${IMAGE_ARCH} \
    torizon/qt5-wayland-vivante:3 AS Deploy

ENV LD_LIBRARY_PATH=/usr/local/lib
# Copy the application source code in the workspace to the $APP_ROOT directory 
# path inside the container, where $APP_ROOT is the torizon_app_root 
# configuration defined in settings.json
COPY ./src /home/torizon/app/src
COPY --from=Build /home/torizon/app/.venv /home/torizon/app/.venv
COPY --from=Build /usr/local/lib /usr/local/lib
COPY --from=Middle /build/usr/lib /usr/lib

RUN apt-get -q -y update && \
    apt-get -q -y install \
      libglib2.0-0 \
      libusb-1.0-0 \
      libxext6 \
    && apt-get clean && apt-get autoremove && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /home/torizon/app/

ENV QT_QPA_PLATFORM="xcb"
ENV APP_ROOT=/home/torizon/app/
ENV USE_GPU_INFERENCE=0

USER torizon
# Activate and run the code
CMD . .venv/bin/activate \
    && python3 src/main.py \
    --delegate=/usr/lib/libvx_delegate.so \
    - i /dev/video2

