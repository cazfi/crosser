# No shebang, this script is not executed, but sourced.

# helpers.sh: Functions for Crosser
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test "x$LOGLEVEL_STDOUT" = "x" ; then
  LOGLEVEL_STDOUT=3
fi
if test "x$LOGLEVEL_FILE" = "x" ; then
  LOGLEVEL_FILE=3
fi

log_init() {
  if ! mkdir -p $MAINLOGDIR
  then
    echo "Failed to create logdir \"$MAINLOGDIR\"" >&2
    return 1
  fi

  log_write 0 "== Build starts =="
  rm -f $MAINLOGDIR/stderr.log
  rm -f $MAINLOGDIR/stdout.log
}

# Call this when starting build of new packet
# $1 - Packet name
log_packet() {
  # Create lines separating output from one packet build from the other
  echo "**** $1 ****" >> $MAINLOGDIR/stdout.log
  echo "**** $1 ****" >> $MAINLOGDIR/stderr.log
}

log_write() {
  DSTAMP=$(date +"%d.%m %H:%M")

  if test "x$1" = "x0" ; then
    echo >> $MAINLOGDIR/main.log
    log_write 1 "======================================"
  fi

  if test $1 -le $LOGLEVEL_FILE ; then
    echo -e "$DSTAMP $STEP:$STEPADD $2" >> $MAINLOGDIR/main.log
  fi

  if test $1 -le $LOGLEVEL_STDOUT ; then
    echo -e "$DSTAMP $STEP:$STEPADD $2"
  fi
}

log_error() {
  log_write 1 "$1"
  echo "$1" >&2
}

log_flags() {
  log_write 4 "  CPPFLAGS: \"$CPPFLAGS\""
  log_write 4 "  CFLAGS:   \"$CFLAGS\""
  log_write 4 "  CXXFLAGS: \"$CXXFLAGS\""
  log_write 4 "  LDFLAGS:  \"$LDFLAGS\""
  log_write 4 "  PATH:     \"$PATH\""
}

generate_setup_scripts() {
  if ! (
    echo "#"\!"/bin/sh"
    echo "export CROSSER=$TARGET"
    echo "export PATH=\"$PATH\""
    echo "export PS1=\"Crosser:> \""
    echo "hash -r"
    echo "/bin/bash --norc"
  ) > $1/setup.sh
  then
    log_error "Failed to create $1/setup.sh"
    return 1
  fi

  chmod a+x $1/setup.sh
}

patch_src() {
  log_write 2 "Patching $1: $2.diff"

  if ! patch -u -p1 -d $MAINSRCDIR/$1 < $MAINDIR/patch/$2.diff \
       >> $MAINLOGDIR/stdout.log 2>> $MAINLOGDIR/stderr.log
  then
    log_error "Patching $1 with $2.diff failed"
    return 1
  fi
}

# $1   - Package name
# $2   - Package version
# [$3] - Subdir in source hierarchy
# [$4] - Package file name in case it cannot be determined automatically
unpack_component() {
  if test "x$DL_ON_DEMAND" = "xyes" ; then
    log_write 1 "Downloading $1 version $2"
    if ! $MAINPACKETDIR/download_latest.sh --packet "$1" \
         >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
    then
      log_error "Failed to download $1 version $2"
      return 1
    fi
  fi

  log_write 1 "Unpacking $1 version $2"

  if test "x$4" != "x" ; then
    # Custom file name format
    if ! tar xzf $MAINPACKETDIR/$4 -C $MAINSRCDIR/$3
    then
      log_error "Unpacking $4 failed"
    fi
  elif test -e $MAINPACKETDIR/$1-$2.tar.bz2 ; then
    if ! tar xjf $MAINPACKETDIR/$1-$2.tar.bz2 -C $MAINSRCDIR/$3
    then
      log_error "Unpacking $1-$2.tar.bz2 failed"
      return 1
    fi
  elif test -e $MAINPACKETDIR/$1-$2.tar.gz ; then
    if ! tar xzf $MAINPACKETDIR/$1-$2.tar.gz -C $MAINSRCDIR/$3
    then
      log_error "Unpacking $1-$2.tar.gz failed"
      return 1
    fi
  elif test -e $MAINPACKETDIR/${1}_${2}.dsc ; then
    if ! which dpkg-source >/dev/null ; then
      log_error "No way to unpack debian source packages"
      return 1
    fi
    if test "x$3" = "x" ; then
      SRCDIR="$1"
    else
      SRCDIR="$3"
    fi
    if ! dpkg-source -x $MAINPACKETDIR/${1}_${2}.dsc $MAINSRCDIR/$SRCDIR
    then
      log_error "Unpacking $1_$2.dsc failed"
      return 1
    fi
  else
    log_error "Can't find $1 version $2 package to unpack."
    return 1
  fi
}

# $1   - Package
# $2   - Version
# [$3] - List of tools to execute, "all" to force use of all tools
autogen_component()
{
  log_packet "autogen $1"

  if test "x$2" = "x" ; then
     SUBDIR="$1"
  else
     SUBDIR="$1-$2"
  fi

  cd $MAINSRCDIR/$SUBDIR

  if test "x$3" = "x" && test -f autogen.sh ; then
    if ! test -x autogen.sh ; then
      log_write 1 "Making $1 autogen.sh executable"
      chmod u+x autogen.sh
    fi
    if ! ./autogen.sh ; then
      log_error "Autogen failed for $1"
      return 1
    fi
  else
    if test "x$3" = "x" || test "x$3" = "xall" ; then
      TOOLS="aclocal automake autoconf"
    else
      TOOLS="$3"
    fi
    for TOOL in $TOOLS
    do
      if ! $TOOL >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
      then
        log_error "Autotool $TOOL failed for $1 version $2"
        return 1
      fi
    done
  fi
}
