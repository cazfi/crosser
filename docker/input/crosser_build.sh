#!/bin/sh -i

# crosser_build.sh : Crosser building script to be used inside the container
#
# (c) 2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

CROSSER_MAINDIR="/crosser"
cd "${CROSSER_MAINDIR}" || exit 1

export CROSSER_FORCE=yes
export CROSSER_TMPDEL=yes

if test "$3" != "" ; then
  export CROSSER_TMPDIR="$3"
fi

. scripts/helpers.sh

CROSSER_FULL=yes CROSSER_LOGDIR=/usr/crosser/log CROSSER_PACKETDIR=/packets \
CROSSER_HOST_PREFIX="/usr/crosser/host/<VERSION>/<VERSIONSET>" \
  ./dllstack.sh "/usr/crosser/win64stack-full-${CROSSER_VERSION}" "$1" "$2"
