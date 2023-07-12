#!/bin/sh -i

# entry.sh : Entry point for the crosser building container 
#
# (c) 2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

su - crosser /build/crosser_build.sh "${CROSSER_VSET}" "${CROSSER_SETUP}"
