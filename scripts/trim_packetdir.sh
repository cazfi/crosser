#!/usr/bin/env bash

# trim_packetdir.sh: Delete old source packets
#
# (c) 2009-2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

declare -i FILELIMIT

FILELIMIT=250

CROSSER_MAINDIR="$(cd "$(dirname "$0")/.." || exit 1 ; pwd)"

if ! test -e "${CROSSER_MAINDIR}/CrosserVersion" && test -e "/usr/share/crosser/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

if ! . "${CROSSER_MAINDIR}/scripts/helpers.sh"
then
  echo "Failed to read ${CROSSER_MAINDIR}/scripts/helpers.sh" >&2
  exit 1
fi

if test "$1" = "-h" || test "$1" = "--help" ; then
  HELP_RETURN=0
elif test "$1" = "" ; then
  HELP_RETURN=1
fi

if test "$1" = "-v" || test "$1" = "--version"
then
  echo "Packetdir trimmer script for Crosser ${CROSSER_VERSION}"
  exit 0
fi

if test "$2" != "" ; then
  FILELIMIT=$2
  if test ${FILELIMIT} -eq 0 ; then
    echo "Illegal filecount parameter \"$2\"" >&2
    exit 1
  fi
fi

if test "${HELP_RETURN}" != "" ; then
  echo "Usage: $(basename "$0") <packetdir> [files left=${FILELIMIT}]"
  exit ${HELP_RETURN}
fi

if ! test -f "$1/filelist.txt" ; then
  echo "Filelist $1/filelist.txt not found!" >&2
  exit 1
fi

# First clean list from files that do not exist
( cat "$1/filelist.txt" | while read F1 F2 F3 F4 F5
  do
    if ! test -e "$1/$F5" ; then
      echo "Removing entry \"$1/$F5\" from filelist as it doesn't exist" >&2
    else
      echo $F1 $F2 $F3 $F4 $F5
    fi
  done
) > "$1/filelist.tmp"

declare -i FILECOUNT=$(wc -l "$1/filelist.tmp" | sed 's/ .*//')

( sort -k 3 "$1/filelist.tmp" | while read F1 F2 F3 F4 F5
  do
    if test ${FILECOUNT} -gt ${FILELIMIT} ; then
      rm "$1/$F5"
      DNAME=$(dirname $F5)
      if test "${DNAME}" != "." ; then
        rmdir "${DNAME}" >/dev/null 2>/dev/null
      fi
      FILECOUNT=${FILECOUNT}-1
    else
      echo $F1 $F2 $F3 $F4 $F5
    fi
  done
) > "$1/filelist.txt"

rm "$1/filelist.tmp"
