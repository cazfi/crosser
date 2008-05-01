#!/bin/sh

CROSSER_VERSION=$(tail -n 1 Version)
FILELIST="packets/download_latest.sh mirrors/finland.conf setups/latest.conf README steps/stepfuncs.sh steps/*.step ChangeLog"

echo "Building Crosser release $CROSSER_VERSION"

if ! rm -f crosser-$CROSSER_VERSION.tar.bz2        ||
   ! tar cf crosser-$CROSSER_VERSION.tar $FILELIST ||
   ! bzip2 -9 crosser-$CROSSER_VERSION.tar
then
  echo "Failed to build tarball" >&2
  exit 1
fi

