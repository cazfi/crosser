#!/bin/bash

# docker_run.sh : Run docker container to build crosser
#
# (c) 2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

CROSSER_MAINDIR="$(cd "$(dirname "$0")/.." || exit 1 ; pwd)"

if test "$1" = "-h" || test "$1" = "--help" ; then
  echo "Usage: $(basename "$0") [-h|--help|version set] [setup]"

  exit 0
fi

if ! test -e "${CROSSER_MAINDIR}/CrosserVersion" &&
     test -e "/usr/share/crosser/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

. "${CROSSER_MAINDIR}/scripts/setup_reader.sh"
. "${CROSSER_MAINDIR}/scripts/helpers.sh"

CROSSER_DOCKER_OUTDIR="$(dirname "$0")/output"

if ! mkdir -p "${CROSSER_DOCKER_OUTDIR}" ; then
  echo "Failed to create an output directory for the container!" >&2
  exit 1
fi

CROSSER_DOCKER_OUTDIR="$(cd "${CROSSER_DOCKER_OUTDIR}" || exit 1 ; pwd)"

docker run \
       --mount type=bind,source="${CROSSER_MAINDIR}",target=/crosser \
       --mount type=bind,source="${CROSSER_PACKETDIR}",target=/packets \
       --mount type=bind,source="${CROSSER_DOCKER_OUTDIR}",target=/usr/crosser/ \
       -e "CROSSER_VSET=$1" \
       -e "CROSSER_SETUP=$2" \
       -t "crosser-bldr-${CROSSER_FEATURE_LEVEL}"
