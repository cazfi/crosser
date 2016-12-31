# No shebang, this script is not executed, but sourced.

# setup_reader.sh: Setup build environment variables
#
# (c) 2008-2016 Marko Lindqvist
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

if test "x$CROSSER_PACKETDIR" = "x" && test "x$PACKETDIR" != "x" ; then
    echo "Configuration variable PACKETDIR is deprecated. Please use CROSSER_PACKETDIR" >&2
    CROSSER_PACKETDIR="$PACKETDIR"
fi
if test "x$CROSSER_PACKETDIR" = "x" ; then
    CROSSER_PACKETDIR="$HOME/.crosser/packets"
fi
if test "x$CROSSER_BUILDDIR" = "x" && test "x$MAINBUILDDIR" != "x"
then
  echo "Configuration variable MAINBUILDDIR is deprecated. Please use CROSSER_BUILDDIR" >&2
  CROSSER_BUILDDIR="$MAINBUILDDIR"
fi
if test "x$CROSSER_BUILDDIR" = "x" ; then
  CROSSER_BUILDDIR="$CROSSER_TMPDIR/build"
fi
if test "x$CROSSER_SRCDIR" = "x" && test "x$MAINSRCDIR" != "x"
then
  echo "Configuration variable MAINSRCDIR is deprecated. Please use CROSSER_SRCDIR" >&2
  CROSSER_SRCDIR="$MAINSRCDIR"
fi
if test "x$CROSSER_SRCDIR" = "x" ; then
  CROSSER_SRCDIR="$CROSSER_TMPDIR/src"
fi
if test "x$CROSSER_LOGDIR" = "x" && test "x$LOGDIR" != "x"
then
  echo "Configuration variable LOGDIR is deprecated. Please use CROSSER_LOGDIR" >&2
  CROSSER_LOGDIR="$LOGDIR"
fi
if test "x$LOGLEVEL_FILE" != "x" && test "x$CROSSER_LOGLVL_FILE" = "x"
then
    echo "Configuration variable LOGLEVEL_FILE is deprecated. Please use CROSSER_LOGLVL_FILE" >&2
    CROSSER_LOGLVL_FILE="$LOGLEVEL_FILE"
fi
if test "x$LOGLEVEL_STDOUT" != "x" && test "x$CROSSER_LOGLVL_STDOUT" = "x"
then
    echo "Configuration variable LOGLEVEL_STDOUT is deprecated. Please use CROSSER_LOGLVL_STDOUT" >&2
    CROSSER_LOGLVL_STDOUT="$LOGLEVEL_STDOUT"
fi
if test "x$CROSSER_LOGDIR" = "x" ; then
  CROSSER_LOGDIR="$HOME/.crosser/log"
fi
if test "x$CROSSER_DOWNLOAD" = "x" ; then
  CROSSER_DOWNLOAD="demand"
fi
if test "x$CROSSER_CORES" != "x" ; then
  declare -i CTMP="$CROSSER_CORES"
  if test $CTMP -lt 1 ; then
    echo "Illegal CROSSER_CORES configure option value \"$CROSSER_CORES\"" >&2
    exit 1
  fi
  CROSSER_MAKEOPTIONS="-j $CROSSER_CORES"
else
  CROSSER_MAKEOPTIONS=""
fi
if test "x$DLLSPREFIX" = "x" && test "x$LSPREFIX" != "x" ; then
  echo "Configuration variable LSPREFIX is deprecated. Please use DLLSPREFIX." >&2
  DLLSPREFIX="$LSPREFIX"
fi
if test "x$DLLSPREFIX" = "x" && test "x$CROSSER_DST_PFX" != "x" ; then
  echo "Configuration variable CROSSER_DST_PFX is deprecated. Please use DLLSPREFIX." >&2
  DLLSPREFIX="$CROSSER_DST_PFX"
fi
if test "x$CROSSER_QT" = "x" ; then
    CROSSER_QT="no"
fi
if test "x$CROSSER_QT" != "xyes" && test "x$CROSSER_QT" != "xno" ; then
    echo "Unknown value \"$CROSSER_QT\" for CROSSER_QT. Valid values are \"yes\" and \"no\"" >&2
    exit 1
fi
if test "x$CROSSER_SDL" = "x" ; then
    CROSSER_SDL="no"
fi
if test "x$CROSSER_SDL" != "xyes" && test "x$CROSSER_SDL" != "xno" ; then
    echo "Unknown value \"$CROSSER_SDL\" for CROSSER_SDL. Valid values are \"yes\" and \"no\"" >&2
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
    CROSSER_PKGCONF="pkg-config"
fi
if test "x$CROSSER_PKGCONF" != "xpkg-config" && test "x$CROSSER_PKGCONF" != "xpkgconf" ; then
    echo "Uknowns value \"$CROSSER_PKGCONF\" for CROSSER_PKGCONF. Valid values are \"pkg-config\" and \"pkgconf" >&2
    exit 1
fi
if test "x$CROSSER_DEFAULT_SETUP" = "x" ; then
    CROSSER_DEFAULT_SETUP="win32"
fi
if test "x$CROSSER_PKGCONF" = "xpkg-config" ; then
    # Use real pkg-config, not recursively the link we create
    CROSSER_PKGCONF="pkg-config.real"
fi
if test "x$CROSSER_WINVER" = "x" ; then
    # Default minimum version is Windows 7
    CROSSER_WINVER=0x0601
fi
