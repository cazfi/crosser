#!/bin/bash

# debian.sh : Crosser requirements installer to be used inside
#             the container.
#
# Almost direct copy from requirements/debian.sh
#
# (c) 2014-2026 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

PACKAGES="\
 mingw-w64 \
 g++-mingw-w64 \
 g++ \
 wget \
 tar \
 gzip \
 bzip2 \
 xz-utils \
 unzip \
 patch \
 libgdk-pixbuf2.0-bin \
 gettext \
 libxml-simple-perl \
 libtiff5-dev \
 xsltproc \
 itstool \
 flex \
 bison \
 docbook-xsl \
 python3-dev \
 intltool \
 cmake \
 imagemagick \
 gperf \
 libxml2-dev \
 graphviz \
 ninja-build \
 sassc \
 gtk-update-icon-cache \
 python3-pygments \
 libclang-dev \
 python3-packaging \
 python3-setuptools \
"

if test "${UID}" != "0" ; then
  echo "You need to be root to install requirement packages" >&2
  exit 1
fi

apt-get install --yes ${PACKAGES}
