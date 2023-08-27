# No shebang, this script is not executed, but sourced.

# packethandlers.sh: Functions for Crosser
#
# (c) 2008-2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

# Helper functions that are not generic enought to be part of helper.sh

READLINE_SHORT="$(echo $VERSION_READLINE | sed 's/\.//g')"

# Apply all patches to readline source tree
#
patch_readline() {
  if test "$VERSION_READLINE" = "0" ; then
    return 0
  fi

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

# Echo sqlite version string
#
# $1 - Version number in dotted format
sqlite_verstr() {
  echo $1 | sed 's/\./ /g' | (read part1 part2 part3 part4
    echo -n ${part1}
    if test "${part4}" = ""
    then
      part4="0"
    fi
    for part in ${part2} ${part3} ${part4}
    do
      if test ${part} -lt 10
      then
        echo -n "0"
      fi
      echo -n ${part}
    done
  )
}

# Echo version number part of icu archive filename
#
# $1 - icu version
icu_filever() {
  echo "$1" | sed -e 's/\./_/g'
}
