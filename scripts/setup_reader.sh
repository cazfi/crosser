# No shebang, this script is not executed, but sourced.

# setup_reader.sh: Setup build environment variables
#
# (c) 2008-2026 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test "$CROSSER_TMPDIR" = ""
then
  CROSSER_TMPDIR="/tmp/crosser-$(whoami)"
fi

if test "$CROSSER_GLOBAL_CONF" = "" && test -e "/etc/crosser.conf" ; then
  CROSSER_GLOBAL_CONF="/etc/crosser.conf"
fi

if test "$CROSSER_GLOBAL_CONF" != "" ; then
  if ! test -e "$CROSSER_GLOBAL_CONF" ; then
    echo "Error: Can't find global configuration file \"$CROSSER_GLOBAL_CONF\"" >&2
    exit 1
  fi
  . "$CROSSER_GLOBAL_CONF"
fi

if test "$CROSSER_CONF" != "" ; then
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
elif test "$CROSSER_GLOBAL_CONF" = "" ; then
  echo "Warning: No configuration found. Trying to build with default values." >&2
  echo "         Read doc/setup.txt for configuration instructions." >&2
fi

if test "$CROSSER_PACKETDIR" = "" ; then
  CROSSER_PACKETDIR="$HOME/.crosser/packets"
fi
if test "$CROSSER_BUILDDIR" = "" ; then
  CROSSER_BUILDDIR="$CROSSER_TMPDIR/build"
fi
if test "$CROSSER_SRCDIR" = "" ; then
  CROSSER_SRCDIR="$CROSSER_TMPDIR/src"
fi
if test "$CROSSER_LOGDIR" = "" ; then
  CROSSER_LOGDIR="$HOME/.crosser/log"
fi
if test "$CROSSER_DOWNLOAD" = "" ; then
  CROSSER_DOWNLOAD="demand"
fi
if test "$CROSSER_CORES" = "" ; then
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

if test "$CROSSER_TMPFREE" != "" && test "$CROSSER_TMPDEL" = "" ; then
  echo "Configuration variable CROSSER_TMPFREE is deprecated. Please use CROSSER_TMPDEL" >&2
  CROSSER_TMPDEL="$CROSSER_TMPFREE"
fi
if test "${CROSSER_HOST_PREFIX}" = "" && test "${DLLSHOST_PREFIX}" != "" ; then
  echo "Configuration variable DLLSHOST_PREFIX is deprecated. Please use CROSSER_HOST_PREFIX" >&2
  CROSSER_HOST_PREFIX="${DLLSHOST_PREFIX}"
fi
if test "$CROSSER_FULL" = "" ; then
  CROSSER_FULL="no"
fi
if test "$CROSSER_FULL" != "yes" && test "$CROSSER_FULL" != "no" ; then
  echo "Unknown value \"$CROSSER_FULL\" for CROSSER_FULL. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "$CROSSER_QT6" = "" ; then
  CROSSER_QT6="$CROSSER_FULL"
fi
if test "$CROSSER_QT6" != "yes" && test "$CROSSER_QT6" != "no" ; then
  echo "Unknown value \"$CROSSER_QT6\" for CROSSER_QT6. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "$CROSSER_GTK4" = "" ; then
  CROSSER_GTK4="yes"
fi
if test "$CROSSER_GTK4" != "yes" && test "$CROSSER_GTK4" != "no" ; then
  echo "Unknown value \"$CROSSER_GTK4\" for CROSSER_GTK4. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "$CROSSER_SDL2" = "" ; then
  CROSSER_SDL2="yes"
fi
if test "$CROSSER_SDL2" != "yes" && test "$CROSSER_SDL2" != "no" ; then
  echo "Unknown value \"$CROSSER_SDL2\" for CROSSER_SDL2. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "${CROSSER_SDL3}" = "" ; then
  CROSSER_SDL3="yes"
fi
if test "${CROSSER_SDL3}" != "yes" && test "${CROSSER_SDL3}" != "no" ; then
  echo "Unknown value \"${CROSSER_SDL3}\" for CROSSER_SDL3. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "${CROSSER_SFML}" = "" ; then
  CROSSER_SFML="${CROSSER_FULL}"
fi
if test "${CROSSER_SFML}" != "yes" && test "${CROSSER_SFML}" != "no" ; then
  echo "Unknown value \"${CROSSER_SFML}\" for CROSSER_SFML. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "${CROSSER_READLINE}" = "" ; then
  CROSSER_READLINE="${CROSSER_FULL}"
fi
if test "${CROSSER_READLINE}" != "yes" && test "${CROSSER_READLINE}" != "no" ; then
  echo "Unknown value \"${CROSSER_READLINE}\" for CROSSER_READLINE. Valid values are \"yes\" and \"no\"" >&2
  exit 1
fi
if test "$CROSSER_PKGCONF" = "" ; then
  CROSSER_PKGCONF="pkgconf"
fi
if test "$CROSSER_PKGCONF" != "pkg-config" && test "$CROSSER_PKGCONF" != "pkgconf" ; then
  echo "Unknown value \"$CROSSER_PKGCONF\" for CROSSER_PKGCONF. Valid values are \"pkg-config\" and \"pkgconf\"" >&2
  exit 1
fi
if test "${CROSSER_WGET}" = "" ; then
  CROSSER_WGET="wget"
fi
if test "${CROSSER_WGET}" != "wget" && test "${CROSSER_WGET}" != "wget2" ; then
  echo "Unknown value \"${CROSSER_WGET}\" for CROSSER_WGET. Valid values are \"wget\" and \"wget2\"" >&2
  exit 1
fi
if test "$CROSSER_DEFAULT_SETUP" = "" ; then
  CROSSER_DEFAULT_SETUP="win64"
fi
if test "$CROSSER_PKGCONF" = "pkg-config" ; then
  # Use real pkg-config, not recursively the link we create
  CROSSER_PKGCONF="pkg-config.real"
fi
if test "$CROSSER_WINVER" = "" ; then
  # Default minimum version is Windows 8.1
  CROSSER_WINVER=0x0603
fi
