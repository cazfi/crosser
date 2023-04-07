#!/bin/bash

# docker_build.sh : Build docker container for building crosser
#
# (c) 2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

if test "$1" = "" ; then
  CROSSER_UID=$(id -u)
else
  CROSSER_UID="$1"
fi

docker build --build-arg CROSSER_UID="$CROSSER_UID" -t "crosser-bldr-2.6" input
