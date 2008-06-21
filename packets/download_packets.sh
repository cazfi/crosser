#!/bin/bash

# download_packets.sh: Source package downloader
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.


# $1 - Base URL
# $2 - Filename
# $3 - Download directory
download_file() {
  if test "x$2" = "x" ; then
    return 0
  fi

  if test "x$3" != "x"
  then
    DLDIR="$3"
  else
    DLDIR="."
  fi

  if ! ( cd $DLDIR && wget "$1$2" ) ; then
    if test "x$CONTINUE" = "xyes" ; then
      echo "Download of $2 failed" >&2
      return 0
    fi
    return 1
  fi
}

# $1 - Base URL
# $2 - Base filename
# $3 - Version      - or nonstandard filename (See $4)
# $4 - Package type - empty means nonstandard naming (See $3)
download_packet() {

  if test "x$4" = "xdsc" ; then
    DLFILENAME="${2}_$3.$4"
    DLFILE2="${2}_$3.diff.gz"
    BASEVERSION=$(echo $3 | sed 's/-.*//')
    DLFILE3="${2}_$BASEVERSION.orig.tar.gz"
  else
    DLFILE2=""
    DLFILE3=""
    if test "x$4" = "x" ; then
      DLFILENAME="$3"
    else
      DLFILENAME="$2-$3.$4"
    fi
  fi

  if test -f "$DLFILENAME" ; then
    if test "x$FORCE" != "xyes" ; then
       echo "Already has $2 version $3, skipping"
       return 0
    fi
    echo "Already has $2 version $3, but forced to load"
  fi

  # Download DLFILENAME last as its presence marks packet download already finished
  # when rerunning download script.
  if ! download_file "$1" "$DLFILE2" ||
     ! download_file "$1" "$DLFILE3" ||
     ! download_file "$1" "$DLFILENAME"
  then
     echo "Download of $2 version $3 failed" >&2
     return 1
  fi

  echo "Downloaded $2 version $3"
}

# $1 - Base URL
# $2 - Base filename
# $3 - Number of patches
download_patches_internal() {

  declare -i DLNUM=1
  declare -i DLTOTAL=$3

  while test $DLNUM -le $DLTOTAL
  do
    if test $DLNUM -lt 10 ; then
      ZEROES="00"
    else
      ZEROES="0"
    fi
    if ! download_file "$1" "${2}${ZEROES}${DLNUM}" "patch"
    then
       echo "Download of $2 patch $DLNUM failed" >&2
       return 1
    fi
    DLNUM=$DLNUM+1
  done
}

# $1 - Base URL
# $2 - Base filename
# $3 - Version
# $4 - Package type
# Return:
# 0 - Downloaded
# 1 - Failure
# 2 - Not needed
download_needed() {
  if test "x$3" != "x"
  then
    PACKVER="$3"
  else
    PACKVER="$VERSION_SELECTED"
  fi

  if test "x$DOWNLOAD_PACKET" != "x" ; then
    if test "x$DOWNLOAD_PACKET" = "x$2" ; then
      download_packet "$1" "$2" "$PACKVER" "$4"
      return $?
    fi
    return 2
  fi
  if test "x$STEPLIST" = "x" ; then
    download_packet "$1" "$2" "$PACKVER" "$4"
    return $?
  fi
  for STEP in $STEPLIST
  do
    if belongs_to_step $2 $STEP ; then
      download_packet "$1" "$2" "$PACKVER" "$4"
      return $?
    fi
  done

  echo "$2 version $PACKVER not needed, skipping"
  return 2
}

# $1 - Base URL
# $2 - Packet name
# $3 - Base filename
# $4 - Version
# $5 - Number of patches
# Return:
# 0 - Downloaded
# 1 - Failure
# 2 - Not needed
download_patches() {
  if test "x$4" != "x"
  then
    PACKVER="$4"
  else
    PACKVER="$VERSION_SELECTED"
  fi

  if test "x$DOWNLOAD_PACKET" != "x" ; then
    if test "x$DOWNLOAD_PACKET" = "x$2" ; then
      download_patches_internal "$1" "$3" "$5"
      return $?
    fi
    return 2
  fi
  if test "x$STEPLIST" = "x" ; then
    download_patches_internal "$1" "$3" "$5"
    return $?
  fi
  for STEP in $STEPLIST
  do
    if belongs_to_step $2 $STEP ; then
      download_patches_internal "$1" "$3" "$5"
      return $?
    fi
  done

  echo "$3 version $PACKVER patches not needed, skipping"
  return 2
}

cd "$(dirname $0)"
MAINDIR="$(cd .. ; pwd)"

if test "x$1" = "x-h" || test "x$1" = "x--help" ; then
  HELP_RETURN=0
elif test "x$1" = "x" ; then
  HELP_RETURN=1
fi

if test "x$HELP_RETURN" != "x" ; then
  echo "Usage: $(basename $0) <step> [versionset]"
  echo "       $(basename $0) --packet <name> [version] [patches]"
  echo
  echo " Possible steps:"
  echo "  - native"
  echo "  - chain"
  echo "  - win"
  echo "  - all"

  exit $HELP_RETURN
fi

if test "x$1" = "x--packet"
then
  if test "x$3" != "x"
  then
    export VERSION_SELECTED="$3"
    if test "x$4" != "x" ; then
      if test "x$2" != "xreadline"
      then
        echo "Number of patches given for component which has no patches." >&2
        exit 1
      fi
      export PATCHES_SELECTED="$4"
    else
      export PATCHES_SELECTED="0"
    fi
  else
    VERSIONSET="current"
  fi
elif test "x$1" != "x--packet" && test "x$2" != "x"
then
  VERSIONSET="$2"
else
  VERSIONSET="current"
fi

if test "x$VERSIONSET" != "x"
then
  if ! test -e $MAINDIR/setups/$VERSIONSET.versions
  then
    echo "Versionset $VERSIONSET.versions not found" >&2
    exit 1
  fi

  if ! . $MAINDIR/setups/$VERSIONSET.versions ; then
    echo "Failed to read list of package versions ($VERSIONSET.versions)" >&2
    exit 1
  fi
fi

if test -e $MAINDIR/mirrors.conf ; then
  if ! . $MAINDIR/mirrors.conf ; then
    echo "Problem in reading list of mirrors to use" >&2
    exit 1
  fi
fi

if ! . $MAINDIR/steps/stepfuncs.sh ; then
  echo "Problem in reading stepfuncs.sh" >&2
  exit 1
fi

if test "x$1" = "x--packet" ; then
  if test "x$2" = "x" ; then
    echo "No packet name given after --packet" >&2
    exit 1
  fi
  DOWNLOAD_PACKET="$2"
else
  STEPLIST="$(parse_steplist $1)"
  RET=$?
  if test "x$RET" != "x0"
  then
    echo "Error in step parameters \"$1\"" >&2
    exit 1
  fi
fi

if test "x$MIRROR_GNU" = "x" ; then
  MIRROR_GNU="ftp://ftp.gnu.org/gnu"
fi

if test "x$MIRROR_GCC" = "x" ; then
  MIRROR_GCC="$MIRROR_GNU/gcc"
fi

if test "x$MIRROR_KERNEL" = "x" ; then
  MIRROR_KERNEL="http://www.all.kernel.org"
fi

if test "x$MIRROR_SOURCEWARE" = "x" ; then
  MIRROR_SOURCEWARE="ftp://sources.redhat.com"
fi

if test "x$MIRROR_DEB" = "x" ; then
  MIRROR_DEB="http://ftp.debian.org/debian"
fi

if test "x$MIRROR_CUPS" = "x" ; then
  MIRROR_CUPS="http://ftp.easysw.com/pub"
fi

MIRROR_SOURCEFORGE="http://downloads.sourceforge.net"
MIRROR_GNOME="http://ftp.gnome.org/pub/gnome"
MIRROR_SAVANNAH="http://download.savannah.gnu.org"

if test "x$VERSION_SELECTED" != "x"
then
  case $DOWNLOAD_PACKET in
    glib)     VERSION_GLIB=$VERSION_SELECTED ;;
    pango)    VERSION_PANGO=$VERSION_SELECTED ;;
    gtk+)     VERSION_GTK=$VERSION_SELECTED ;;
    atk)      VERSION_ATK=$VERSION_SELECTED ;;
    gcc)      VERSION_GCC=$VERSION_SELECTED ;;
    cups)     VERSION_CUPS=$VERSION_SELECTED ;;
    readline) VERSION_READLINE=$VERSION_SELECTED
              PATCHES_READLINE=$PATCHES_SELECTED ;;
  esac
fi
GLIB_DIR="$(echo $VERSION_GLIB | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
PANGO_DIR="$(echo $VERSION_PANGO | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK_DIR="$(echo $VERSION_GTK | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
ATK_DIR="$(echo $VERSION_ATK | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"

READLINE_SHORT="$(echo $VERSION_READLINE | sed 's/\.//g')"

download_needed "$MIRROR_GNU/libtool/"  "libtool"  "$VERSION_LIBTOOL"  "tar.bz2"

RET="$?"  
download_needed "$MIRROR_GNU/binutils/" "binutils" "$VERSION_BINUTILS" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/gawk/"     "gawk"     "$VERSION_GAWK"     "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/autoconf/" "autoconf" "$VERSION_AUTOCONF" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/automake/" "automake" "$VERSION_AUTOMAKE" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GCC/gcc-$VERSION_GCC/" "gcc" "$VERSION_GCC" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/glibc/"    "glibc" "$VERSION_GLIBC" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/glibc/"    "glibc-libidn" "$VERSION_GLIBC" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/glibc/"    "glibc-ports"  "$VERSION_GLIBC" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_KERNEL/pub/linux/kernel/v2.6/" "linux" "$VERSION_KERNEL"  "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_SOURCEWARE/pub/newlib/"        "newlib" "$VERSION_NEWLIB" "tar.gz"
RET="$RET $?"
download_needed "http://ftp.sunet.se/pub/gnu/gmp/"      "gmp"    "$VERSION_GMP"    "tar.bz2"
RET="$RET $?"
download_needed "http://www.mpfr.org/mpfr-current/"     "mpfr"   "$VERSION_MPFR"   "tar.bz2"
RET="$RET $?"

download_needed "$MIRROR_GNU/libiconv/"                 "libiconv"   "$VERSION_ICONV"      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/libpng/"           "libpng"     "$VERSION_PNG"        "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_DEB/pool/main/z/zlib/"         "zlib"       "$VERSION_ZLIB"       "dsc"
RET="$RET $?"
download_needed "$MIRROR_GNU/ncurses/"                  "ncurses"    "$VERSION_NCURSES"    "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNU/readline/"                 "readline"   "$VERSION_READLINE"   "tar.gz"
RET="$RET $?"
download_patches "$MIRROR_GNU/readline/"                "readline" \
                 "readline-$VERSION_READLINE-patches/readline${READLINE_SHORT}-" \
                 "$VERSION_READLINE"   "$PATCHES_READLINE"
RET="$RET $?"
download_needed "$MIRROR_GNU/gettext/"                  "gettext"    "$VERSION_GETTEXT"    "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/glib/$GLIB_DIR/" "glib"       "$VERSION_GLIB"       "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_DEB/pool/main/libj/libjpeg6b/" "libjpeg6b"  "$VERSION_JPEG"       "dsc"
RET="$RET $?"
download_needed "ftp://ftp.remotesensing.org/pub/libtiff/" "tiff"    "$VERSION_TIFF"       "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/expat/"            "expat"      "$VERSION_EXPAT"      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SAVANNAH/releases/freetype/"   "freetype"   "$VERSION_FREETYPE"   "tar.bz2"
RET="$RET $?"
download_needed "http://fontconfig.org/release/"        "fontconfig" "$VERSION_FONTCONFIG" "tar.gz"
RET="$RET $?"
download_needed "http://cairographics.org/releases/"    "cairo"      "$VERSION_CAIRO"      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/pango/$PANGO_DIR/" "pango"    "$VERSION_PANGO"      "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/atk/$ATK_DIR/"   "atk"        "$VERSION_ATK"        "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gtk+/$GTK_DIR/"  "gtk+"       "$VERSION_GTK"        "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_CUPS/cups/$VERSION_CUPS/"     "cups"       "cups-$VERSION_CUPS-source.tar.bz2"
RET="$RET $?"
download_needed "http://www.libsdl.org/release/"        "SDL"        "$VERSION_SDL"        "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_image/release/" "SDL_image"  "$VERSION_SDL_IMAGE"  "tar.gz"
RET="$RET $?"

for VALUE in $RET
do
  if test "$VALUE" = "0" ; then
    DOWNLOADED=true
  elif test "$VALUE" = "1" ; then
    FAILED=true
  fi
done

if test "x$DOWNLOAD_PACKET" != "x" && test "x$DOWNLOADED" != "xtrue" ; then
  echo "Download instructions for $DOWNLOAD_PACKET not found." >&2
  exit 1
fi

if test "x$FAILED" = "xtrue" ; then
  echo "Some packet(s) failed to download." >&2
  exit 1
fi
