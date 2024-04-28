#!/bin/sh -i

# entry.sh : Entry point for the crosser building container 
#
# (c) 2023-2024 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

CROSSER_DOCKER_USER="$(cat /build/username.txt)"

su - "${CROSSER_DOCKER_USER}" /build/crosser_build.sh "${CROSSER_VSET}" "${CROSSER_SETUP}" "${CROSSER_TMPDIR}"
