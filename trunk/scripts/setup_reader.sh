# No shebang, this script is not executed, but sourced.

# setup_reader.sh: Setup build environment variables
#
# (c) 2008-2010 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test -e $CROSSER_MAINDIR/local_setup.conf ; then
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
if test "x$MAINBUILDDIR" = "x" ; then
  MAINBUILDDIR="$CROSSER_MAINDIR/tmp/build"
fi
if test "x$MAINSRCDIR" = "x" ; then
  MAINSRCDIR="$CROSSER_MAINDIR/tmp/src"
fi
if test "x$LOGDIR" = "x" ; then
  LOGDIR="$HOME/.crosser/log"
fi
if test "x$CROSSER_DOWNLOAD" = "x" ; then
  CROSSER_DOWNLOAD="demand"
fi
if test "x$DLLSPREFIX" = "x" && test "x$LSPREFIX" != "x" ; then
  echo "Configuration variable LSPREFIX is deprecated. Please use DLLSPREFIX." >&2
  DLLSPREFIX="$LSPREFIX"
fi
if test "x$DLLSPREFIX" = "x" && test "x$PREFIX" != "x" ; then
  DLLSPREFIX="$PREFIX"
fi
