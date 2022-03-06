# No shebang, this script is not executed, but sourced.

# setup_reader.sh: Setup build environment variables
#
# (c) 2008-2022 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test "x$CROSSER_TMPDIR" = "x"
then
  CROSSER_TMPDIR="/tmp/crosser-$(whoami)"
fi

if test "x$CROSSER_GLOBAL_CONF" = "x" && test -e "/etc/crosser.conf" ; then
  CROSSER_GLOBAL_CONF="/etc/crosser.conf"
fi

if test "x$CROSSER_GLOBAL_CONF" != "x" ; then
  if ! test -e "$CROSSER_GLOBAL_CONF" ; then
    echo "Error: Can't find global configuration file \"$CROSSER_GLOBAL_CONF\"" >&2
    exit 1
  fi
  . "$CROSSER_GLOBAL_CONF"
fi

if test "x$CROSSER_CONF" != "x" ; then
  if test -e "$CROSSER_CONF" ; then
    . "$CROSSER_CONF"
  else
    echo "Error: Can't find specified configuration file \"$CROSSER_CONF\"" >&2
    exit 1
  fi
elif test -e $CROSSER_MAINDIR/local_setup.conf ; then
  . $CROSSER_MAINDIR/local_setup.conf
elif test -e $HOME/.crosser.conf ; then
  . $HOME/.crosser.conf
elif test "x$CROSSER_GLOBAL_CONF" = "x" ; then
  echo "Warning: No configuration found. Trying to build with default values." >&2
  echo "         Read doc/setup.txt for configuration instructions." >&2
fi

if test "x$CROSSER_PACKETDIR" = "x" ; then
    CROSSER_PACKETDIR="$HOME/.crosser/packets"
fi
if test "x$CROSSER_BUILDDIR" = "x" ; then
  CROSSER_BUILDDIR="$CROSSER_TMPDIR/build"
fi
if test "x$CROSSER_SRCDIR" = "x" ; then
  CROSSER_SRCDIR="$CROSSER_TMPDIR/src"
fi
if test "x$CROSSER_LOGDIR" = "x" ; then
  CROSSER_LOGDIR="$HOME/.crosser/log"
fi
if test "x$CROSSER_DOWNLOAD" = "x" ; then
  CROSSER_DOWNLOAD="demand"
fi
if test "x$CROSSER_CORES" = "x" ; then
  declare -i CROSSER_CORES
  CROSSER_CORES=$(nproc)
  CROSSER_CORES=$CROSSER_CORES+1
fi

declare -i CTMP="$CROSSER_CORES"
if test $CTMP -lt 1 ; then
  echo "Illegal CROSSER_CORES configure option value \"$CROSSER_CORES\"" >&2
  exit 1
fi
CROSSER_COREOPTIONS="-j $CROSSER_CORES"

if test "$CROSSER_TMPFREE" != "" && test "$CROSSER_TMPDEL" = "x" ; then
  echo "Configuration variable CROSSER_TMPFREE is deprecated. Please use CROSSER_TMPDEL" >&2
  CROSSER_TMPDEL="$CROSSER_TMPDEL"
fi
if test "x$CROSSER_FULL" = "x" ; then
  CROSSER_FULL="no"
fi
if test "x$CROSSER_FULL" != "xyes" && test "x$CROSSER_FULL" != "xno" ; then
  echo "Unknown value \"$CROSSER_FULL\" for CROSSER_FULL. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "x$CROSSER_QT5" = "x" && test "x$CROSSER_QT" != "x" ; then
  echo "Configuration variable CROSSER_QT is deprecated. Please use CROSSER_QT5" >&2
  CROSSER_QT5="$CROSSER_QT"
fi
if test "x$CROSSER_QT5" = "x" ; then
  CROSSER_QT5="$CROSSER_FULL"
fi
if test "x$CROSSER_QT5" != "xyes" && test "x$CROSSER_QT5" != "xno" ; then
  echo "Unknown value \"$CROSSER_QT5\" for CROSSER_QT5. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "x$CROSSER_QT6" = "x" ; then
  CROSSER_QT6="$CROSSER_FULL"
fi
if test "x$CROSSER_QT6" != "xyes" && test "x$CROSSER_QT6" != "xno" ; then
  echo "Unknown value \"$CROSSER_QT6\" for CROSSER_QT6. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "x$CROSSER_GTK4" = "x" ; then
    CROSSER_GTK4="$CROSSER_FULL"
fi
if test "x$CROSSER_GTK4" != "xyes" && test "x$CROSSER_GTK4" != "xno" ; then
    echo "Unknown value \"$CROSSER_GTK4\" for CROSSER_GTK4. Valid values are \"yes\" and \"no\"" >&2
    exit 1
fi
if test "x$CROSSER_SDL2" = "x" ; then
    CROSSER_SDL2="yes"
fi
if test "x$CROSSER_SDL2" != "xyes" && test "x$CROSSER_SDL2" != "xno" ; then
    echo "Unknown value \"$CROSSER_SDL2\" for CROSSER_SDL2. Valid values are \"yes\" and \"no\"" >&2
    exit 1
fi
if test "x$CROSSER_SFML" = "x" ; then
    CROSSER_SFML="no"
fi
if test "x$CROSSER_SFML" != "xyes" && test "x$CROSSER_SFML" != "xno" ; then
    echo "Unknown value \"$CROSSER_SFML\" for CROSSER_SFML. Valid values are \"yes\" and \"no\"" >&2
    exit 1
fi
if test "x$CROSSER_READLINE" = "x" ; then
    CROSSER_READLINE="no"
fi
if test "x$CROSSER_READLINE" != "xyes" && test "x$CROSSER_READLINE" != "xno" ; then
    echo "Unknown value \"$CROSSER_READLINE\" for CROSSER_READLINE. Valid values are \"yes\" and \"no\"" >&2
    exit 1
fi
if test "x$CROSSER_PKGCONF" = "x" ; then
    CROSSER_PKGCONF="pkgconf"
fi
if test "x$CROSSER_PKGCONF" != "xpkg-config" && test "x$CROSSER_PKGCONF" != "xpkgconf" ; then
    echo "Unknown value \"$CROSSER_PKGCONF\" for CROSSER_PKGCONF. Valid values are \"pkg-config\" and \"pkgconf" >&2
    exit 1
fi
if test "x$CROSSER_DEFAULT_SETUP" = "x" ; then
    CROSSER_DEFAULT_SETUP="win64"
fi
if test "x$CROSSER_PKGCONF" = "xpkg-config" ; then
    # Use real pkg-config, not recursively the link we create
    CROSSER_PKGCONF="pkg-config.real"
fi
if test "x$CROSSER_WINVER" = "x" ; then
    # Default minimum version is Windows 7
    CROSSER_WINVER=0x0601
fi
