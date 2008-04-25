#!/bin/dash

# $1 - Base URL
# $2 - Base filename
# $3 - Version
# $4 - Package type
download_packet() {
  DLFILENAME="$2-$3.$4"
  if test -f "$DLFILENAME" ; then
    if test "x$FORCE" != "xyes" ; then
       echo "Already has $2 version $3, skipping"
       return 0
    fi
    echo "Already has $2 version $3, but forced to load"
  fi
  if ! wget "$1$DLFILENAME" ; then
     echo "Download of $2 version $3 failed" >&2
     if test "x$CONTINUE" = "xyes" ; then
       return 0
     fi
     return 1
  fi

  echo "Downloaded $2 version $3"
}

MAINDIR="$(cd $(dirname $0)/.. ; pwd)"

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

download_packet "$MIRROR_GNU/binutils/" "binutils" $VERSION_BINUTILS "tar.bz2"
download_packet "$MIRROR_GCC/gcc-$VERSION_GCC/" "gcc" $VERSION_GCC "tar.bz2"
download_packet "$MIRROR_GNU/glibc/" "glibc" $VERSION_GLIBC "tar.bz2"
download_packet "$MIRROR_GNU/glibc/" "glibc-libidn" $VERSION_GLIBC "tar.bz2"
download_packet "$MIRROR_KERNEL/pub/linux/kernel/v2.6/" "linux" $VERSION_KERNEL "tar.bz2"
download_packet "$MIRROR_SOURCEWARE/pub/newlib/" "newlib" $VERSION_NEWLIB "tar.gz"
download_packet "http://ftp.sunet.se/pub/gnu/gmp/" "gmp" $VERSION_GMP "tar.bz2"
download_packet "http://www.mpfr.org/mpfr-current/" "mpfr" $VERSION_MPFR "tar.bz2"
