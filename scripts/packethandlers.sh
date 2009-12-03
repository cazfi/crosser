# No shebang, this script is not executed, but sourced.

# packethandlers.sh: Functions for Crosser
#
# (c) 2008-2009 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

# Helper functions that are not generic enought to be part of helper.sh

READLINE_SHORT="$(echo $VERSION_READLINE | sed 's/\.//g')"

patch_readline() {
  declare -i DLNUM=1
  declare -i DLTOTAL=$PATCHES_READLINE

  while test $DLNUM -le $DLTOTAL
  do
    if test $DLNUM -lt 10 ; then
      ZEROES="00"
    else
      ZEROES="0"
    fi
    if ! upstream_patch readline-$VERSION_READLINE readline${READLINE_SHORT}-${ZEROES}$DLNUM
    then
      return 1
    fi
    DLNUM=$DLNUM+1
  done
}

# Echo base version of libtool version string
#
# $1 - Full version
basever_libtool() {
  if cmp_versions $VERSION_LIBTOOL 2.2.6a
  then
    echo $1 | sed 's/[a-z]//g'
  else
    echo $1
  fi
}
