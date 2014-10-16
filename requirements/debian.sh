#!/bin/bash

# requirements/debian.sh: Crosser requirements installer for Debian system
#
# (c) 2014 Marko Lindqvist
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
 patch \
 libgtk2.0-dev \
 gettext \
 libxml-simple-perl \
 libtiff5-dev \
 xsltproc \
 intltool \
"

if test "$UID" != "0" ; then
  echo "You need to be root to install requirement packages" >&2
  exit 1
fi

apt-get install $PACKAGES
