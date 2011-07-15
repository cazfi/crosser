# No shebang, this script is not executed, but sourced.

# setup_reader.sh: Setup build environment variables
#
# (c) 2008-2011 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test "x$CROSSER_TMPDIR" = "x"
then
  CROSSER_TMPDIR="/tmp/crosser"
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
else
  echo "Warning: No local configuration found. Trying to build with default values." >&2
  echo "         Read doc/setup.txt for configuration instructions." >&2
fi

if test "x$PACKETDIR" = "x" ; then
  PACKETDIR="$HOME/.crosser/packets"
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
if test "x$CROSSER_LOGDIR" = "x" ; then
  CROSSER_LOGDIR="$HOME/.crosser/log"
fi
if test "x$CROSSER_DOWNLOAD" = "x" ; then
  CROSSER_DOWNLOAD="demand"
fi
if test "x$CROSSER_DST_PFX" = "x" && test "x$PREFIX" != "x" ; then
  echo "Configuration variable PREFIX is deprecated. Please use CROSSER_DST_PFX." >&2
  CROSSER_DST_PFX="$PREFIX"
fi
if test "x$DLLSPREFIX" = "x" && test "x$LSPREFIX" != "x" ; then
  echo "Configuration variable LSPREFIX is deprecated. Please use DLLSPREFIX." >&2
  DLLSPREFIX="$LSPREFIX"
fi
if test "x$DLLSPREFIX" = "x" && test "x$CROSSER_DST_PFX" != "x" ; then
  DLLSPREFIX="$CROSSER_DST_PFX"
fi
