# No shebang, this script is not executed, but sourced.

# helpers.sh: Functions for Crosser
#
# (c) 2008-2009 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

#############################################################################

# Generic function to compile one component
#
# $1   - Build directory in build hierarchy
# $2   - Sourcedir in source hierarchy
# $3   - Configure options
# $4   - Make targets
# [$5] - Build in srcdir ('yes')
build_generic() {
  log_packet "$1"

  if test "x$5" != "xyes"
  then
    if test -d "$MAINBUILDDIR/$1"
    then
      rm -Rf "$MAINBUILDDIR/$1"
    fi

    if ! mkdir -p $MAINBUILDDIR/$1
    then
       log_error "Failed to create directory \"$MAINBUILDDIR/$1\""
       return 1
    fi
    if ! cd $MAINBUILDDIR/$1
    then
       log_error "Failed to change workdir to \"$MAINBUILDDIR/$1\""
       return 1
    fi
  else
    if ! cd $MAINSRCDIR/$2
    then
       log_error "Failed to change workdir to \"$MAINSRCDIR/$2\""
       return 1
    fi
  fi

  log_write 1 "Configuring $2"
  log_write 3 "  Options: \"$3\""
  log_flags

  if ! "$MAINSRCDIR/$2/configure" $3 \
      2>>$MAINLOGDIR/stderr.log >>$MAINLOGDIR/stdout.log
  then
    log_error "Configure failed: $1"
    return 1
  fi

  if test "x$4" != "x-" ; then
    if test "x$4" != "x" ; then
      MKTARGETS="$4"
    else
      MKTARGETS="all install"
    fi

    # We need old, dummy, libc.so for running configure for glibc itself,
    # but it has to be removed before we make real one.
    if test "x$1" = "xtgt-glibc" && test -e "$SYSPREFIX/usr/lib/libc.so"
    then
      log_write 3 "  Removing old libc.so"
      rm -f "$SYSPREFIX/usr/lib/libc.so"
    fi

    if test "x$CROSSER_CORES" != "x"
    then
       COREOPT="-j $CROSSER_CORES"
    fi

    log_write 1 "Building $2"
    log_write 3 "  Make targets: $MKTARGETS"
    if ! make $COREOPT $MKTARGETS \
        2>>$MAINLOGDIR/stderr.log >>$MAINLOGDIR/stdout.log
    then
      log_error "Make failed: $1"
      return 1
    fi
  fi

  hash -r

  return 0
}

# Build with compiler built in native step
#
# $1 - Component to compile
# $2 - Sourcedir in source hierarchy
# $3 - Configure options
# $4 - Make targets
build_with_native_compiler() {
  CONFOPTIONS="--build=$BUILD --host=$BUILD --target=$TARGET --prefix=$CROSSPREFIX $3 --disable-nls"

  export CFLAGS="-O2"
  export CPPFLAGS=""
  export LDFLAGS=""

  if ! build_generic "cross-$1" "$2" "$CONFOPTIONS" "$4"
  then
    return 1
  fi
}

# Build component using cross-compiler
#
# $1   - Component name
# $2   - Source dir in source hierarchy
# $3   - Configure options
# $4   - Make targets
# [$5] - Destdir
build_with_cross_compiler() {
  if test "x$3" = "x"
  then
    PREFIXOPTION="--prefix=/usr"
  else
    PREFIXOPTION=""
  fi
  CONFOPTIONS="--build=$BUILD --host=$TARGET --target=$TARGET $PREFIXOPTION $3 --disable-nls"

  export CFLAGS="-O2"
  export CPPFLAGS="-isystem $SYSPREFIX/include -isystem $SYSPREFIX/usr/include"
  export LDFLAGS="-L$SYSPREFIX/lib -L$SYSPREFIX/usr/lib"

  if test "x$4" = "x"
  then
    MAKETARGETS="all install"
  else
    MAKETARGETS="$4"
  fi

  if test "x$5" = "x"
  then
    DESTDIR="$SYSPREFIX"
  else
    DESTDIR="$5"
  fi

  if ! build_generic "tgt-$1" "$2" "$CONFOPTIONS" "DESTDIR=$DESTDIR $MAKETARGETS"
  then
    return 1
  fi
}

# Build component to native directory hierarchy
#
# $1   - Component name
# $2   - Source dir in source hierarchy
# $3   - Configure options
# $4   - Make targets
build_for_host() {
  CONFOPTIONS="--build=$BUILD --host=$BUILD --target=$BUILD --prefix=$NATIVE_PREFIX $3"

  export CFLAGS="-march=native -O2"
  export CPPFLAGS=""
  export LDFLAGS="-Wl,-rpath,$NATIVE_PREFIX/lib -L$NATIVE_PREFIX/lib"

  if ! build_generic "host-$1" "$2" "$CONFOPTIONS" "$4"
  then
    return 1
  fi
}
