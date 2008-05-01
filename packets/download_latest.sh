#!/bin/sh

# $1 - Base URL
# $2 - Filename
download_file() {
  if test "x$2" = "x" ; then
    return 0
  fi

  if ! wget "$1$2" ; then
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
# $3 - Version
# $4 - Package type   
# Return:
# 0 - Downloaded
# 1 - Failure
# 2 - Not needed
download_needed() {
  if test "x$DOWNLOAD_PACKET" != "x" ; then
    if test "x$DOWNLOAD_PACKET" = "x$2" ; then
      download_packet "$1" "$2" "$3" "$4"
      return $?
    fi
    return 2
  fi
  if test "x$STEPLIST" = "x" ; then
    download_packet "$1" "$2" "$3" "$4"
    return $?
  fi
  for STEP in $STEPLIST
  do
    if belongs_to_step $2 $STEP ; then
      download_packet "$1" "$2" "$3" "$4"
      return $?
    fi
  done

  echo "$2 version $3 not needed, skipping"
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
  echo "Usage: $(basename $0) <step>"
  echo "       $(basename $0) --packet <name>"
  echo
  echo " Possible steps:"
  echo "  - native"
  echo "  - chain"
  echo "  - win"
  echo "  - all"

  exit $HELP_RETURN
fi

if test "x$1" = "x--packet" ; then
  if test "x$2" = "x" ; then
    echo "No packet name given after --packet" >&2
    exit 1
  fi
  DOWNLOAD_PACKET="$2"
else
  if test "x$1" = "xnative" ; then
    STEPLIST="native"
  elif test "x$1" = "xchain" ; then
    STEPLIST="chain"
  elif test "x$1" = "xwin" ; then
    STEPLIST="win"
  elif test "x$1" != "xall" ; then
    echo "Unknown step \"$1\"" >&2
    exit 1
  fi
fi

if ! . $MAINDIR/setups/latest.conf ; then
  echo "Failed to read list of package versions" >&2
  exit 1
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

MIRROR_SOURCEFORGE="http://downloads.sourceforge.net"
MIRROR_GNOME="http://ftp.gnome.org/pub/gnome"
MIRROR_SAVANNAH="http://download.savannah.gnu.org"

GLIB_DIR="$(echo $VERSION_GLIB | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"

download_needed "$MIRROR_GNU/binutils/" "binutils" $VERSION_BINUTILS "tar.bz2"
RET="$?"
download_needed "$MIRROR_GCC/gcc-$VERSION_GCC/" "gcc" $VERSION_GCC "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/glibc/" "glibc" $VERSION_GLIBC "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/glibc/" "glibc-libidn" $VERSION_GLIBC "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/glibc/" "glibc-ports"  $VERSION_GLIBC "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_KERNEL/pub/linux/kernel/v2.6/" "linux" $VERSION_KERNEL "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_SOURCEWARE/pub/newlib/" "newlib" $VERSION_NEWLIB "tar.gz"
RET="$RET $?"
download_needed "http://ftp.sunet.se/pub/gnu/gmp/" "gmp" $VERSION_GMP "tar.bz2"
RET="$RET $?"
download_needed "http://www.mpfr.org/mpfr-current/" "mpfr" $VERSION_MPFR "tar.bz2"
RET="$RET $?"

download_needed "$MIRROR_GNU/libiconv/"                 "libiconv"   $VERSION_ICONV      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/libpng/"           "libpng"     $VERSION_PNG        "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_DEB/pool/main/z/zlib/"         "zlib"       $VERSION_ZLIB       "dsc"
RET="$RET $?"
download_needed "$MIRROR_GNU/gettext/"                  "gettext"    $VERSION_GETTEXT    "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/glib/$GLIB_DIR/" "glib"       $VERSION_GLIB       "tar.bz2"
RET="$RET $?"
download_needed "http://www.ijg.org/files/"             "jpeg"    jpegsrc.v$VERSION_JPEG.tar.gz ""
RET="$RET $?"
download_needed "ftp://ftp.remotesensing.org/pub/libtiff/" "tiff"    $VERSION_TIFF       "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/expat/"            "expat"      $VERSION_EXPAT      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SAVANNAH/releases/freetype/"   "freetype"   $VERSION_FREETYPE   "tar.bz2"
RET="$RET $?"
download_needed "http://fontconfig.org/release/"        "fontconfig" $VERSION_FONTCONFIG "tar.gz"
RET="$RET $?"
download_needed "http://cairographics.org/releases/"    "cairo"      $VERSION_CAIRO      "tar.gz"
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
