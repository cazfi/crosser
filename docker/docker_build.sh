#!/usr/bin/env bash

# docker_build.sh : Build docker container for building crosser
#
# (c) 2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

CROSSER_MAINDIR="$(cd "$(dirname "$0")/.." || exit 1 ; pwd)"

if test "$1" = "-h" || test "$1" = "--help" ; then
  echo "Usage: $(basename "$0") [-h|--help]|[uid=current user]"
  exit 0
fi

if ! test -e "${CROSSER_MAINDIR}/CrosserVersion" &&
     test -e "/usr/share/crosser/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

. "${CROSSER_MAINDIR}/scripts/setup_reader.sh"
. "${CROSSER_MAINDIR}/scripts/helpers.sh"

if test "$1" = "" ; then
  CROSSER_UID="$(id -u)"
else
  CROSSER_UID="$1"
fi

docker build --build-arg CROSSER_UID="${CROSSER_UID}" \
       -t "crosser-bldr-${CROSSER_FEATURE_LEVEL}" input
