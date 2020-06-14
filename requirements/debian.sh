#!/bin/bash

# requirements/debian.sh: Crosser requirements installer for
#                         Debian system and derivatives
#
# (c) 2014-2020 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

PACKAGES="\
 mingw-w64 g++-mingw-w64 \
 wget \
 tar \
 gzip \
 bzip2 \
 xz-utils \
 unzip \
 patch \
 libgtk2.0-dev \
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
 xmlto \
"

if test "$UID" != "0" ; then
  echo "You need to be root to install requirement packages" >&2
  exit 1
fi

apt install $PACKAGES
