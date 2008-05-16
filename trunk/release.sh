#!/bin/sh

# release.sh: Release builder for Crosser
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

CROSSER_VERSION=$(tail -n 1 Version)
FILELIST="packets/download_packets.sh mirrors/finland.conf setups/current.versions doc/README steps/stepfuncs.sh steps/stepset.sh steps/*.step doc/ChangeLog COPYING scripts/helpers.sh scripts/aux/install-sh scripts/aux/ltmain.sh scripts/aux/config.guess scripts/aux/config.sub"

echo "Building Crosser release $CROSSER_VERSION"

if ! rm -f crosser-$CROSSER_VERSION.tar.bz2        ||
   ! tar cf crosser-$CROSSER_VERSION.tar $FILELIST ||
   ! bzip2 -9 crosser-$CROSSER_VERSION.tar
then
  echo "Failed to build tarball" >&2
  exit 1
fi

