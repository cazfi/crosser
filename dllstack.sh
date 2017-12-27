#!/bin/bash

# dllstack.sh: Cross-compile set of libraries for Windows target.
#
# (c) 2008-2017 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

#############################################################################################
#
# Preparations
#

CROSSER_MAINDIR="$(cd "$(dirname "$0")" ; pwd)"

if ! test -e "$CROSSER_MAINDIR/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

if test "x$1" = "x-h" || test "x$1" = "x--help"
then
  echo "Usage: $(basename "$0") [[-h|--help]|[-v|--version]|[install prefix]] [versionset] [setup]"
  exit 0
fi

# In order to give local setup opportunity to override versions,
# we have to load versionset before setup_reader.sh
# helpers.sh requires environment to be set up by setup_reader.sh.
if test "x$2" != "x" ; then
  CROSSER_VERSIONSET="$2"
else
  CROSSER_VERSIONSET="current"
fi
if test -e "$CROSSER_MAINDIR/setups/${CROSSER_VERSIONSET}.versions"
then
  . "$CROSSER_MAINDIR/setups/${CROSSER_VERSIONSET}.versions"
else
  # Versions being unset do not prevent loading of setup_reader.sh and helper.sh,
  # resulting environment would just be unusable for building.
  # We are not going to build anything, but just issuing error message - and for
  # that we read log_error from helpers.sh
  CROSSER_ERR_MSG="Cannot find versionset \"${CROSSER_VERSIONSET}.versions\""
fi

. "$CROSSER_MAINDIR/scripts/setup_reader.sh"
. "$CROSSER_MAINDIR/scripts/helpers.sh"
. "$CROSSER_MAINDIR/scripts/packethandlers.sh"

# This must be after reading helpers.sh so that $CROSSER_VERSION is set
if test "x$1" = "x-v" || test "x$1" = "x--version"
then
  echo "Windows library stack builder for Crosser $CROSSER_VERSION"
  exit 0
fi

if test "x$3" = "x"
then
  CROSSER_SETUP="$CROSSER_DEFAULT_SETUP"
else
  CROSSER_SETUP="$3"
fi

if ! log_init
then
  echo "Cannot setup logging!" >&2
  exit 1
fi

if test "x$CROSSER_ERR_MSG" != "x"
then
  log_error "$CROSSER_ERR_MSG"
  exit 1
fi

if test "x$1" != "x"
then
  DLLSPREFIX="$1"
fi

################################################################################################
#
# Functions
#

# $1 - Component
# $2 - Extra configure options
build_component()
{
  build_component_full "$1" "$1" "$2"
}

# $1   - Component
# $2   - Extra configure options
# [$3] - "native", "cross", or "pkg-config"
build_component_host()
{
  if test "x$3" = "xpkg-config"
  then
    BTYPE="$3"
    BDTYPE="cross"
  else
    if test "x$3" != "x"
    then
      BTYPE="$3"
    else
      BTYPE="native"
    fi
    BDTYPE="$BTYPE"
  fi
  if ! build_component_full "$BDTYPE-$1" "$1" "$2" "$BTYPE"
  then
    BERR=true
  else
    BERR=false
  fi

  # Reset command hash in case it already contained old version of the
  # just built tool
  hash -r

  if test "x$BERR" = "xtrue"
  then
    return 1
  fi
}

# $1   - Build dir or 'src'
# $2   - Component
# $3   - Extra configure options
# [$4] - Build type ('native' | 'windres' | 'cross' | 'qt' | 'pkg-config' | 'custom')
# [$5] - Src subdir
# [$6] - Make options
# [$7] - Version
build_component_full()
{
  log_packet "$2"

  if test "x$7" != "x"
  then
    BVER="$7"
  else
    BVER="$(component_version $2)"
  fi

  if test "x$BVER" = "x"
  then
    log_error "Version for $2 not defined"
    return 1
  fi

  if test "x$BVER" = "x0"
  then
    return 0
  fi

  if test "x$2" = "xgtk2" || test "x$2" = "xgtk3" || test "x$2" = "xgtk4"
  then
    BNAME="gtk+"
  else
    BNAME="$2"
  fi

  if test "x$5" != "x"
  then
    SUBDIR="$5"
    if ! test -d "$CROSSER_SRCDIR/$SUBDIR"
    then
      log_error "$BNAME srcdir \"$5\" doesn't exist"
      return 1
    fi
  else
    SUBDIR="$(src_subdir $BNAME $BVER)"
    if test "x$SUBDIR" = "x"
    then
      log_error "Cannot find srcdir for $BNAME version $BVER"
      return 1
    fi
  fi

  if test "x$1" != "xsrc"
  then
    DISPLAY_NAME="$1"
    BUILDDIR="$CROSSER_BUILDDIR/$1"
    if ! mkdir -p "$BUILDDIR"
    then
      log_error "Failed to create directory $BUILDDIR"
      return 1
    fi
    SRCDIR="$CROSSER_SRCDIR/$SUBDIR"
  else
    DISPLAY_NAME="$2"
    BUILDDIR="$CROSSER_SRCDIR/$SUBDIR"
    SRCDIR="."  
  fi

  (
  cd "$BUILDDIR"

  if test "x$4" = "xnative"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xcross"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX --build=$CROSSER_BUILD_ARCH --host=$CROSSER_BUILD_ARCH --target=$CROSSER_TARGET $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xpkg-config"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX --program-prefix=$CROSSER_TARGET- $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xcustom"
  then
    CONFOPTIONS="--prefix=${DLLSPREFIX} $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xwindres"
  then
    CONFOPTIONS="--prefix=$DLLSPREFIX --build=$CROSSER_BUILD_ARCH --host=$CROSSER_TARGET --target=$CROSSER_TARGET $3"
    unset CPPFLAGS
    export LDFLAGS="-L$DLLSPREFIX/lib -static-libgcc $CROSSER_STDCXX"
    export CC="$CROSSER_TARGET-gcc -static-libgcc"
    export CXX="$CROSSER_TARGET-g++ $CROSSER_STDCXX -static-libgcc"
  elif test "x$4" = "xqt"
  then
    CONFOPTIONS="-prefix $DLLSPREFIX $3"
  else
    CONFOPTIONS="--prefix=$DLLSPREFIX --build=$CROSSER_BUILD_ARCH --host=$CROSSER_TARGET --target=$CROSSER_TARGET $3"
    export CPPFLAGS="-I$DLLSPREFIX/include -I$TGT_HEADERS $CROSSER_WINVER_FLAG"
    export LDFLAGS="-L$DLLSPREFIX/lib -static-libgcc $CROSSER_STDCXX"
    export CC="$CROSSER_TARGET-gcc -static-libgcc"
    export CXX="$CROSSER_TARGET-g++ $CROSSER_STDCXX -static-libgcc"
  fi

  if test -x "$SRCDIR/configure"
  then
    log_write 1 "Configuring $DISPLAY_NAME"
    log_write 3 "  Options: \"$CONFOPTIONS\""
    log_flags

    if ! "$SRCDIR/configure" $CONFOPTIONS >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log
    then
      log_error "Configure for $DISPLAY_NAME failed"
      return 1
    fi
  elif test -f "$SRCDIR/CMakeLists.txt"
  then
    cmake -DCMAKE_SYSTEM_NAME="Windows" -DCMAKE_INSTALL_PREFIX="${DLLSPREFIX}" "$SRCDIR" >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log
  fi

  log_write 1 "Building $DISPLAY_NAME"
  log_write 3 "  Make targets: [default] install"
  if test "x$6" = "xno"
  then
    MAKEOPTIONS=""
  elif test "x$6" != "x"
  then
    MAKEOPTIONS="$6"
  else
    MAKEOPTIONS="$CROSSER_COREOPTIONS"
  fi
  log_write 4 "  Options: \"$MAKEOPTIONS\""

  if ! make $MAKEOPTIONS >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $DISPLAY_NAME failed"
    return 1
  fi

  if ! make $MAKEOPTIONS install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Install for $DISPLAY_NAME failed"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "$DISPLAY_NAME : $BVER" >> $DLLSPREFIX/ComponentVersions.txt
  fi

  return $RET
}

# $1 - Build dir
# $2 - Component
# $3 - Extra meson options
build_with_meson()
{
  log_packet "$2"

  BVER=$(component_version $2)

  if test "x$BVER" = "x"
  then
    log_error "Version for $2 not definer"
    return 1
  fi

  if test "x$BVER" = "x0"
  then
    return 0
  fi

  if test "x$2" = "xgtk4"
  then
    BNAME="gtk+"
  else
    BNAME="$2"
  fi

  SUBDIR="$(src_subdir $BNAME $BVER)"
  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $BNAME version $BVER"
    return 1
  fi

  DISPLAY_NAME="$1"

  BUILDDIR="$CROSSER_BUILDDIR/$1"
  if ! mkdir -p "$BUILDDIR"
  then
    log_error "Failed to create directory $BUILDDIR"
    return 1
  fi
  SRCDIR="$CROSSER_SRCDIR/$SUBDIR"

  (
  cd "$BUILDDIR"

  export CPPFLAGS="-I$DLLSPREFIX/include -I$TGT_HEADERS $CROSSER_WINVER_FLAG"
  export LDFLAGS="-L$DLLSPREFIX/lib -static-libgcc $CROSSER_STDCXX"

  log_write 1 "Running meson for $DISPLAY_NAME"
  log_write 3 "  Options: $3"

  if ! meson $SRCDIR . --cross-file $DLLSPREFIX/etc/meson_cross_file.txt \
       --prefix=$DLLSPREFIX $3 \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Meson for $DISPLAY_NAME failed"
    return 1
  fi

  log_write 1 "Running ninja for $DISPLAY_NAME"

  if ! ninja install \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Ninja for $DISPLAY_NAME failed"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "$DISPLAY_NAME : $BVER" >> $DLLSPREFIX/ComponentVersions.txt
  fi

  return $RET
}

# Build zlib
#
# $1 - Package name
# $2 - Version
# $3 - Configure options
#
build_zlib()
{
  log_packet "$1"

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  BUILDDIR="$CROSSER_BUILDDIR/$1"
  if ! mkdir -p "$BUILDDIR"
  then
    log_error "Failed to create directory $BUILDDIR"
    return 1
  fi
  SRCDIR="$CROSSER_SRCDIR/$SUBDIR"

  (
  export CC="$CROSSER_TARGET-gcc -static-libgcc"
  export RANLIB="$CROSSER_TARGET-ranlib"
  export AR="$CROSSER_TARGET-ar"

  if ! cd "$BUILDDIR"
  then
    log_error "Cannot change to directory $BUILDDIR"
    return 1
  fi

  export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS $CROSSER_WINVER_FLAG"
  export LDFLAGS="-L$DLLSPREFIX/lib"

  CONFOPTIONS="--prefix=$DLLSPREFIX --shared $3"

  # TODO: zlib build doesn't like this variable, check why.
  unset TARGET_ARCH

  log_write 1 "Configuring $1"
  log_write 3 "  Options: \"$CONFOPTIONS\""
  log_flags

  if ! $SRCDIR/configure $CONFOPTIONS >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Configure for $1 failed"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default] install"
  log_write 4 "  Options: \"$CROSSER_COREOPTIONS\""

  if ! make $CROSSER_COREOPTIONS \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make $CROSSER_COREOPTIONS install \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Install for $1 failed"
    return 1
  fi

  if ! cp "$DLLSPREFIX/lib/libz.dll"* "$DLLSPREFIX/bin/" ||
     ! mv "$DLLSPREFIX/lib/libz.a"    "$DLLSPREFIX/bin/"
  then
    log_error "Failed to move libz dll:s to correct directory"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "$1 : $2" >> $DLLSPREFIX/ComponentVersions.txt
  fi

  return $RET
}

# Build bzip2/win-iconv
#
# $1 - Package name
# $2 - Version
#
build_simple_make()
{
  log_packet "$1"

  if test "x$2" = "x0"
  then
    return 0
  fi

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  (
  if ! cd "$CROSSER_SRCDIR/$SUBDIR"
  then
    log_error "Cannot change to directory $CROSSER_SRCDIR/$SUBDIR"
    return 1
  fi

  export CC="$CROSSER_TARGET-gcc -static-libgcc"
  export RANLIB="$CROSSER_TARGET-ranlib"
  export AR="$CROSSER_TARGET-ar"
  export DLLTOOL="$CROSSER_TARGET-dlltool"
  export PREFIX=$DLLSPREFIX
  export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS $CROSSER_WINVER_FLAG"
  export LDFLAGS="-L$DLLSPREFIX/lib"

  log_write 1 "Building $1"
  if test "x$1" = "xbzip2"
  then
      MKTARGETS="libbz2.a bzip2 bzip2recover"
      MAKEOPTIONS="$CROSSER_COREOPTIONS"
  elif test "x$1" = "xwin-iconv"
  then
      MKTARGETS="all"
      MAKEOPTIONS=""
  fi
  log_write 3 " Make targets: $MKTARGETS & install"
  log_write 4 "  Options: \"$MAKEOPTIONS\""
  log_flags

  if ! make $MAKEOPTIONS $MKTARGETS \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make $MAKEOPTIONS prefix="$DLLSPREFIX" install \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Install for $1 failed"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "$1 : $2" >> $DLLSPREFIX/ComponentVersions.txt
  fi

  return $RET
}

# Build PDCurses
#
# $1 - Package name
# $2 - Version
#
build_pdcurses()
{
  if test "x$2" = "x0"
  then
    return 0
  fi

  log_packet "$1"

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  (
  if ! cd "$CROSSER_SRCDIR/$SUBDIR/win32"
  then
    log_error "Cannot change to directory $CROSSER_SRCDIR/$SUBDIR/win32"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default]"
  log_write 4 "  Options: \"$CROSSER_COREOPTIONS\""

  if ! make -f mingwin32.mak $CROSSER_COREOPTIONS \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! cp pdcurses.a "$DLLSPREFIX/lib/libpdcurses.a"
  then
      log_error "pdcurses.a copy failed"
      return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "$1 : $2" >> $DLLSPREFIX/ComponentVersions.txt
  fi

  return $RET
}

#######################################################################################################
#
# Main
#

cd $(dirname $0)

CROSSER_BUILD_ARCH="$($CROSSER_MAINDIR/scripts/aux/config.guess)"

if ! test -e "$CROSSER_MAINDIR/setups/$CROSSER_SETUP.conf" ; then
  log_error "Can't find setup \"$CROSSER_SETUP.conf\""
  exit 1
fi
. "$CROSSER_MAINDIR/setups/$CROSSER_SETUP.conf"

if test "x$DLLSTACK" = "xno"
then
  log_error "dllstack.sh cannot be used with configuration \"$CROSSER_SETUP\"."
  exit 1
fi

if test "x$TARGET_VENDOR" = "x"
then
  export CROSSER_TARGET="$TARGET_ARCH-$TARGET_OS"
else
  export CROSSER_TARGET="$TARGET_ARCH-$TARGET_VENDOR-$TARGET_OS"
fi

if test -d "/usr/$CROSSER_TARGET/include"
then
  export TGT_HEADERS="/usr/$CROSSER_TARGET/include"
fi

if test "x$DLLSHOST_PREFIX" = "x" && test "x$LSHOST_PREFIX" != "x" ; then
  echo "Configuration variable LSHOST_PREFIX is deprecated. Please use DLLSHOST_PREFIX." >&2
  DLLSHOST_PREFIX="$LSHOST_PREFIX"
fi

export DLLSPREFIX=$(setup_prefix_default "$HOME/.crosser/<VERSION>/<VERSIONSET>/<SETUP>/winstack" "$DLLSPREFIX")
export NATIVE_PREFIX=$(setup_prefix_default "$HOME/.crosser/<VERSION>/<VERSIONSET>/dllshost" \
                       "$DLLSHOST_PREFIX")

TARGET_GCC_VER=$($CROSSER_TARGET-gcc -dumpversion | sed 's/-.*//')
TARGET_GXX_VER=$($CROSSER_TARGET-g++ -dumpversion | sed 's/-.*//')

CROSSER_WINVER_FLAG="-D_WIN32_WINNT=${CROSSER_WINVER}"

log_write 2 "Install:    \"$DLLSPREFIX\""
log_write 2 "Src:        \"$CROSSER_SRCDIR\""
log_write 2 "Log:        \"$CROSSER_LOGDIR\""
log_write 2 "Build:      \"$CROSSER_BUILDDIR\""
log_write 2 "Setup:      \"$CROSSER_SETUP\""
log_write 2 "Versionset: \"$CROSSER_VERSIONSET\""
log_write 2 "cross-gcc:  $TARGET_GCC_VER"
log_write 2 "cross-g++:  $TARGET_GXX_VER"

CROSSER_STDCXX="-static-libstdc++"

remove_dir "$CROSSER_SRCDIR" && remove_dir "$CROSSER_BUILDDIR" && remove_dir "$DLLSPREFIX" && remove_dir "$NATIVE_PREFIX"
RDRET=$?

if test "x$RDRET" = "x1" ; then
    log_error "Old directories not removed"
    exit 1
elif test "x$RDRET" != "x0" ; then
    log_error "Failed to remove old directories"
    exit 1
fi

if ! mkdir -p "$CROSSER_SRCDIR"
then
  log_error "Cannot create directory $CROSSER_SRCDIR"
  exit 1
fi

if ! mkdir -p "$CROSSER_BUILDDIR"
then
  log_error "Cannot create directory $CROSSER_BUILDDIR"
  exit 1
fi

if ! mkdir -p "$DLLSPREFIX/man/man1" ||
   ! mkdir -p "$DLLSPREFIX/etc"
then
  log_error "Cannot create target directory hierarchy under $DLLSPREFIX"
  exit 1
fi

if ! mkdir -p "$NATIVE_PREFIX/bin"
then
  log_error "Cannot create host directory hierarchy under $NATIVE_PREFIX"
  exit 1
fi

export PATH="$NATIVE_PREFIX/bin:$PATH"

if ! packetdir_check
then
  log_error "Packetdir missing"
  exit 1
fi

log_write 1 "Creating meson cross file"

(
  TARGET_GCC=$(which $CROSSER_TARGET-gcc)
  TARGET_GPP=$(which $CROSSER_TARGET-g++)
  TARGET_AR=$(which $CROSSER_TARGET-ar)
  TARGET_STRIP=$(which $CROSSER_TARGET-strip)
  TARGET_PKGCONFIG=$NATIVE_PREFIX/bin/$CROSSER_TARGET-pkg-config

  if test "x$TARGET_GCC" = "x" ||
     test "x$TARGET_GPP" = "x" ||
     test "x$TARGET_AR" = "x"  ||
     test "x$TARGET_STRIP" = "x"
  then
    log_error "Cross-tools missing"
    exit 1
  fi
  if ! sed -e "s,<TARGET_GCC>,$TARGET_GCC,g" \
           -e "s,<TARGET_GPP>,$TARGET_GPP,g" \
           -e "s,<TARGET_AR>,$TARGET_AR,g" \
           -e "s,<TARGET_STRIP>,$TARGET_STRIP,g" \
           -e "s,<TARGET_PKGCONFIG>,$TARGET_PKGCONFIG,g" \
           $CROSSER_MAINDIR/scripts/$MESON_CROSS_FILE \
           > $DLLSPREFIX/etc/meson_cross_file.txt
  then
    log_error "Meson cross-file creation failed"
    exit 1
  fi
)

if test "x$CROSSER_DOWNLOAD" = "xyes"
then
    if test "x$CROSSER_SDL" = "xyes" ; then
        steplist="win,sdl"
    else
        steplist="win"
    fi
    if test "x$CROSSER_SDL2" = "xyes" ; then
        steplist="${steplist},sdl2"
    fi
    if test "x$CROSSER_SFML" = "xyes" ; then
        steplist="${steplist},sfml"
    fi
    if test "x$CROSSER_QT" = "xyes" ; then
        steplist="${steplist},full"
    fi
    if ! (cd "$CROSSER_PACKETDIR" &&
          "$CROSSER_MAINDIR/scripts/download_packets.sh" "$steplist" "$CROSSER_VERSIONSET")
  then
    log_error "Downloading packets failed"
    exit 1
  fi
fi

BASEVER_LIBTOOL="$(basever_libtool $VERSION_LIBTOOL)"
GLIB_VARS="$(read_configure_vars glib)"
GETTEXT_VARS="$(read_configure_vars gettext)"
IM_VARS="$(read_configure_vars imagemagick)"
CAIRO_VARS="$(read_configure_vars cairo)"
ICU_FILEVER="$(icu_filever $VERSION_ICU)"

export LD_LIBRARY_PATH="${NATIVE_PREFIX}/lib"

if ! unpack_component     autoconf                          ||
   ! build_component_host autoconf                          ||
   ! free_component       autoconf   $VERSION_AUTOCONF "native-autoconf" ||
   ! unpack_component     automake                          ||
   ! build_component_host automake                          ||
   ! free_component       automake   $VERSION_AUTOMAKE "native-automake" ||
   ! unpack_component     libtool                           ||
   ! build_component_full native-libtool libtool            \
     "" "native" "" "" "$BASEVER_LIBTOOL"                   ||
   ! free_build           "native-libtool"                               ||
   ! unpack_component     libffi                            ||
   ! build_component_host libffi                            ||
   ! free_build           "native-libffi"                   ||
   ! unpack_component     pkgconf                                           ||
   ! mv "$CROSSER_SRCDIR/pkgconf-pkgconf-$VERSION_PKGCONF" "$CROSSER_SRCDIR/pkgconf-$VERSION_PKGCONF" ||
   ! autogen_component pkgconf $VERSION_PKGCONF                             || 
   ! build_component_host pkgconf                                           \
     "--with-pkg-config-dir=$NATIVE_PREFIX/lib/pkgconfig"                   ||
   ! free_component       pkgconf $VERSION_PKGCONF native-pkgconf           ||
   ! unpack_component     pkg-config                                        ||
   ! build_component_host pkg-config                                        \
     "--with-pc-path=$NATIVE_PREFIX/lib/pkgconfig --with-internal-glib --disable-compile-warnings"    ||
   ! free_build           "native-pkg-config"                               ||
   ! unpack_component     pcre                                              ||
   ! patch_src pcre $VERSION_PCRE "pcre_test_disable"                       ||
   ! patch_src pcre $VERSION_PCRE "pcre_doublemacros"                       ||
   ! build_component_host pcre                                              \
     "--enable-unicode-properties"                                          ||
   ! free_build           "native-pcre"                                     ||
   ! unpack_component     pcre2                                             ||
   ! build_component_host pcre2                                             \
     "--enable-unicode-properties"                                          ||
   ! free_build           "native-pcre2"                                    ||
   ! unpack_component     glib                                              ||
   ! build_component_host glib                                              \
     "--disable-libmount"                                                   ||
   ! free_build           "native-glib"                                     ||
   ! unpack_component     gtk-doc                                           ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_pc"                         ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_configheaders"              ||
   ! autogen_component    gtk-doc $VERSION_GTK_DOC                          ||
   ! build_component_host gtk-doc                                           ||
   ! free_component  gtk-doc   $VERSION_GTK_DOC                             \
     "native-gtk-doc"                                                       ||
   ! unpack_component     gobject-introspection                             ||
   ! build_component_host gobject-introspection                             ||
   ! free_component  gobject-introspection   $VERSION_GOBJ_INTRO            \
     "native-gobject-introspection"                                         ||
   ! build_component_host pkg-config                                        \
     "--with-pc-path=$DLLSPREFIX/lib/pkgconfig --disable-host-tool" "pkg-config" ||
   ! free_component       pkg-config $VERSION_PKG_CONFIG "cross-pkg-config"      ||
   ! mv $NATIVE_PREFIX/bin/pkg-config $NATIVE_PREFIX/bin/pkg-config.real         ||
   ! ln -s $CROSSER_PKGCONF $NATIVE_PREFIX/bin/pkg-config                        ||
   ! unpack_component  icon-naming-utils                                    ||
   ! patch_src icon-naming-utils $VERSION_ICON_NUTILS "icon-nutils-pc"      ||
   ! build_component_host icon-naming-utils                                 ||
   ! free_component    icon-naming-utils $VERSION_ICON_NUTILS               \
     "native-icon-naming-utils"                                             ||
   ! unpack_component  icu4c         "" "icu4c-$ICU_FILEVER-src"            ||
   ! patch_src icu $VERSION_ICU icu_dbl_mant                                ||
   ! (is_smaller_version $VERSION_ICU 58.1 ||
      is_minimum_version $VERSION_ICU 60.1 ||
      patch_src icu $VERSION_ICU icu_locale )                               ||
   ! (is_smaller_version $VERSION_ICU 60.1 ||
      patch_src icu $VERSION_ICU icu_locale_60 )                            ||
   ! (is_smaller_version $VERSION_ICU 59.1 ||
      is_minimum_version $VERSION_ICU 60.1 ||
      ( patch_src icu $VERSION_ICU icu_uloc_slash &&
        patch_src icu $VERSION_ICU icu_mbstowcs_params ))                   ||
   ! (is_smaller_version $VERSION_ICU 59.1 ||
      patch_src icu $VERSION_ICU icu_filetools_inc )                        ||
   ! (is_minimum_version $VERSION_ICU 60 ||
      patch_src icu $VERSION_ICU icu_xlocale_no )                           ||
   ! CXX="g++" CFLAGS="-fPIC" build_component_full native-icu4c icu4c ""    \
     "native" "icu/source"                                                  ||
   ! unpack_component tiff                                                  ||
   ! patch_src tiff $VERSION_TIFF tiff_config_headers_395                   ||
   ! build_component_host tiff                                              ||
   ! free_build           "native-tiff"                                     ||
   ! unpack_component     libxml2                                           ||
   ! build_component_host libxml2 "--without-python"                        ||
   ! free_build           "native-libxml2"                                  ||
   ! unpack_component  shared-mime-info                                     ||
   ! ln -s "../lib/pkgconfig" "$NATIVE_PREFIX/share/pkgconfig"              ||
   ! build_component_host shared-mime-info                                  ||
   ! free_build           "native-shared-mime-info"                         ||
   ! unpack_component gdk-pixbuf                                            ||
   ! (is_smaller_version $VERSION_GDK_PIXBUF 2.36.5 ||
      patch_src gdk-pixbuf $VERSION_GDK_PIXBUF gdk_pixbuf_tnrm )            ||
   ! build_component_host gdk-pixbuf                                        ||
   ! free_build           "native-gdk-pixbuf"                               ||
   ! unpack_component     util-macros                                       ||
   ! build_component_host util-macros                                       ||
   ! free_component       util-macros $VERSION_UTIL_MACROS                  \
     "native-util-macros"                                                   ||
   ! unpack_component     libpng                                            ||
   ! patch_src            libpng      $VERSION_PNG "png_epsilon-1.6.8"      ||
   ! build_component_host libpng                                            ||
   ! free_build           "native-libpng"                                   ||
   ! unpack_component     ImageMagick                                       ||
   ! patch_src ImageMagick $VERSION_IMAGEMAGICK "im_pthread"                ||
   ! (( is_minimum_version $VERSION_IMAGEMAGICK 7.0.0 &&
        ( is_minimum_version $VERSION_IMAGEMAGICK 7.0.2 ||
          patch_src ImageMagick $VERSION_IMAGEMAGICK "im_intsafe_not_7" ) &&
        patch_src ImageMagick $VERSION_IMAGEMAGICK "im_nobin_7" ) ||
      ( patch_src ImageMagick $VERSION_IMAGEMAGICK "im_nobin" &&
        patch_src ImageMagick $VERSION_IMAGEMAGICK "im_fchmod_avoid" &&
        patch_src ImageMagick $VERSION_IMAGEMAGICK "im_intsafe_not" ))      ||
   ! build_component_host ImageMagick                                       ||
   ! free_build           "native-ImageMagick"
then
  log_error "Native build failed"
  exit 1
fi

SQL_VERSTR="$(sqlite_verstr $VERSION_SQLITE)"
READLINE_VARS="$(read_configure_vars readline)"

if ! build_component_full libtool libtool "" "" "" ""                 \
     "${BASEVER_LIBTOOL}"                                             ||
   ! free_component    libtool    $BASEVER_LIBTOOL "libtool"          ||
   ! unpack_component  win-iconv  "" "win-iconv/v${VERSION_WIN_ICONV}" ||
   ! build_simple_make win-iconv  $VERSION_WIN_ICONV                  ||
   ! free_src          win-iconv  $VERSION_WIN_ICONV                  ||
   ! unpack_component  libiconv                                       ||
   ! build_component   libiconv                                       ||
   ! free_component    libiconv   $VERSION_ICONV "libiconv"           ||
   ! unpack_component  zlib                                           ||
   ! patch_src zlib $VERSION_ZLIB zlib_seeko-1.2.6-2                  ||
   ! patch_src zlib $VERSION_ZLIB zlib_nolibc-1.2.6-2                 ||
   ! patch_src zlib $VERSION_ZLIB zlib_dllext                         ||
   ! build_zlib        zlib       $VERSION_ZLIB                       ||
   ! free_src          zlib       $VERSION_ZLIB                       ||
   ! unpack_component  bzip2                                          ||
   ! patch_src bzip2 $VERSION_BZIP2 bzip2_unhardcodecc                ||
   ! patch_src bzip2 $VERSION_BZIP2 bzip2_incpathsep                  ||
   ! patch_src bzip2 $VERSION_BZIP2 bzip2_winapi                      ||
   ! build_simple_make bzip2      $VERSION_BZIP2                      ||
   ! free_src          bzip2      $VERSION_BZIP2                      ||
   ! unpack_component  xz                                             ||
   ! build_component_full xz xz   "--disable-threads" "windres"       ||
   ! free_component    xz         $VERSION_XZ "xz"                    ||
   ! unpack_component  curl                                           ||
   ! patch_src curl $VERSION_CURL curl_winpollfd                      ||
   ! build_component   curl       "--disable-pthreads"                ||
   ! free_component    curl       $VERSION_CURL "curl"                ||
   ! unpack_component  sqlite                                                        \
     "" "sqlite-autoconf-${SQL_VERSTR}"                                              ||
   ! build_component_full sqlite sqlite                                              \
     "--disable-threadsafe" "" "sqlite-autoconf-${SQL_VERSTR}"                       ||
   ! free_component    sqlite-autoconf $SQL_VERSTR "sqlite"                          ||
   ! build_component_full icu4c icu4c                                                \
     "--with-cross-build=$CROSSER_BUILDDIR/native-icu4c" "" "icu/source"             ||
   ! free_build           "native-icu4c"                                             ||
   ! free_component    icu        $VERSION_ICU "icu4c"                               ||
   ! ((is_minimum_version $VERSION_IMAGEMAGICK 7.0.0 &&
       patch_src ImageMagick $VERSION_IMAGEMAGICK "im_free_locale_comment_7" &&
       patch_src ImageMagick $VERSION_IMAGEMAGICK "im_link_ws2_7" ) ||
      (patch_src ImageMagick $VERSION_IMAGEMAGICK "im_free_locale_comment" &&
       patch_src ImageMagick $VERSION_IMAGEMAGICK "im_link_ws2" ))                   ||
   ! build_component   ImageMagick                                                   \
     "--without-bzlib --without-threads --without-magick-plus-plus --disable-openmp" ||
   ! free_component    ImageMagick $VERSION_IMAGEMAGICK "ImageMagick"                ||
   ! build_component   libpng                                                        ||
   ! free_component    libpng     $VERSION_PNG "libpng"                              ||
   ! unpack_component  gettext                                                       ||
   ! (is_smaller_version $VERSION_GETTEXT 0.19 ||
      patch_src         gettext    $VERSION_GETTEXT "gettext_nolibintl_inc")         ||
   ! LIBS="-liconv" build_component gettext                                          \
     "$GETTEXT_VARS --enable-relocatable --enable-threads=windows --disable-libasprintf"    ||
   ! free_component    gettext    $VERSION_GETTEXT "gettext"                         ||
   ! build_component   pcre                                           \
     "--disable-cpp --enable-unicode-properties"                      ||
   ! free_component    pcre       $VERSION_PCRE    "pcre"             ||
   ! build_component   pcre2                                          \
     "--disable-cpp --enable-unicode-properties --enable-pcre2-16"    ||
   ! free_component    pcre2      $VERSION_PCRE2    "pcre2"           ||
   ! build_component   libffi                                         ||
   ! free_component    libffi     $VERSION_FFI     "libffi"           ||
   ! build_component   glib       "$GLIB_VARS --with-threads=win32"   ||
   ! free_component    glib       $VERSION_GLIB    "glib"
then
  log_error "Build failed"
  exit 1
fi

if test "x$CROSSER_READLINE" = "xyes" ; then
if ! unpack_component  PDCurses                                          ||
   ! patch_src PDCurses $VERSION_PDCURSES "PDCurses_crosswin"            ||
   ! build_pdcurses    PDCurses $VERSION_PDCURSES                        \
     "--without-x"                                                       ||
   ! free_src          PDCurses $VERSION_PDCURSES                        ||
   ! unpack_component  readline                                          ||
   ! patch_readline                                                      ||
   ! patch_src readline $VERSION_READLINE "readline_posix"               ||
   ! ((is_minimum_version $VERSION_READLINE 7.0 &&
       patch_src readline $VERSION_READLINE "readline_chown" ) ||
      patch_src readline $VERSION_READLINE "readline_sighup" )           ||
   ! patch_src readline $VERSION_READLINE "readline_statf"               ||
   ! patch_src readline $VERSION_READLINE "readline_pdcurses"            ||
   ! build_component   readline                                          \
     "$READLINE_VARS --with-curses"                                      ||
   ! free_component    readline   $VERSION_READLINE "readline"
then
  log_error "Readline build failed"
  exit 1
fi
fi

if ! unpack_component jpeg  "" "jpegsrc.v${VERSION_JPEG}"             ||
   ! build_component jpeg "--enable-shared"                           ||
   ! free_component jpeg $VERSION_JPEG "jpeg"
then
  log_error "Libjpeg build failed"
  exit 1
fi
CONF_JPEG_GTK="--without-libjasper"

if ! build_component   tiff                                                 ||
   ! free_component    tiff       $VERSION_TIFF "tiff"                      ||
   ! build_component   libxml2                                              \
     "--without-python --with-zlib=$DLLSPREFIX --with-lzma=$DLLSPREFIX"     ||
   ! free_component    libxml2    $VERSION_XML2 "libxml2"                   ||
   ! build_component_full shared-mime-info shared-mime-info "" "" ""        \
     "no"                                                                   ||
   ! free_component    shared-mime-info $VERSION_SHARED_MIME_INFO           \
     "shared-mime-info"                                                     ||
   ! unpack_component  jansson                                              ||
   ! build_component   jansson                                              ||
   ! free_component    jansson    $VERSION_JANSSON "jansson"                ||
   ! unpack_component  freetype                                             ||
   ! build_component   freetype   "--without-bzip2"                         ||
   ! free_component    freetype   $VERSION_FREETYPE "freetype"              ||
   ! unpack_component  harfbuzz                                             ||
   ! build_component   harfbuzz   "--without-icu"                           ||
   ! free_component    harfbuzz   $VERSION_HARFBUZZ "harfbuzz"              ||
   ! unpack_component  fontconfig                                           ||
   ! ( is_smaller_version $VERSION_FONTCONFIG 2.12.3 ||
       patch_src       fontconfig $VERSION_FONTCONFIG fontconfig_fcobjs_prototypes ) ||
   ! build_component   fontconfig                                           \
     "--with-freetype-config=$DLLSPREFIX/bin/freetype-config --with-arch=$CROSSER_TARGET --enable-libxml2" ||
   ! free_component    fontconfig $VERSION_FONTCONFIG "fontconfig"          ||
   ! unpack_component  glew                                                 ||
   ! patch_src         glew $VERSION_GLEW glew_mingw                        ||
   ! build_component_full src glew                                          ||
   ! unpack_component  libepoxy                                             ||
   ! build_component   libepoxy                                             ||
   ! free_component    libepoxy $VERSION_LIBEPOXY "libepoxy"                ||
   ! unpack_component  pixman                                               ||
   ! patch_src          pixman $VERSION_PIXMAN pixman_epsilon               ||
   ! build_component   pixman                                               \
     "--disable-gtk"                                                        ||
   ! free_component    pixman     $VERSION_PIXMAN "pixman"                  ||
   ! unpack_component  cairo                                                ||
   ! rm -f "$CROSSER_SRCDIR/cairo-$VERSION_CAIRO/src/cairo-features.h"      ||
   ! patch_src         cairo $VERSION_CAIRO cairo-1.12.10_epsilon           ||
   ! patch_src         cairo $VERSION_CAIRO cairo_ffs                       ||
   ! ( is_minimum_version    $VERSION_CAIRO 1.15.2 ||
       patch_src       cairo $VERSION_CAIRO cairo_1.14.2+ )                 ||
   ! build_component   cairo "$CAIRO_VARS --disable-xlib --enable-win32"    ||
   ! free_component    cairo      $VERSION_CAIRO "cairo"                    ||
   ! unpack_component  pango                                                ||
   ! build_component   pango                                                ||
   ! free_component    pango      $VERSION_PANGO "pango"                    ||
   ! unpack_component  atk                                                  ||
   ! build_component   atk                                                  ||
   ! free_component    atk        $VERSION_ATK "atk"
then
  log_error "Build failed"
  exit 1
fi

if test "x$CROSSER_GTK2" = "xno" ; then
    if test "x$CROSSER_GTK3" = "xno" ; then
        CROSSER_GTK=no
    else
        VERSION_GTK2=0
        VERSION_GTK_ENG=0
        VERSION_GNOME_THEME_STD=0
    fi
else
    if test "x$CROSSER_GTK3" = "xno" ; then
        VERSION_GTK3=no
    fi
fi

if test "x$CROSSER_GTK" != "xno" ; then
if ! build_component  gdk-pixbuf "--enable-relocations"               ||
   ! free_component   gdk-pixbuf $VERSION_GDK_PIXBUF "gdk-pixbuf"     ||
   ! unpack_component gtk2                                            ||
   ! build_component  gtk2                                            \
     "--disable-cups --disable-explicit-deps --with-included-immodules $CONF_JPEG_GTK" ||
   ! free_component   gtk+        $VERSION_GTK2 "gtk2"                ||
   ! unpack_component gtk3                                            ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gdk/gdkconfig.h         ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gtk/gtk.gresource.xml   ||
   ! ( is_smaller_version $VERSION_GTK3 3.20.0 ||
       is_minimum_version $VERSION_GTK3 3.21.1 ||
       patch_src gtk+ $VERSION_GTK3 gtk3_demoless-3.20 )              ||
   ! ( is_smaller_version $VERSION_GTK3 3.22.9 ||
       patch_src gtk+ $VERSION_GTK3 gtk3_demoless-3.22.9 )            ||
   ! patch_src gtk+ $VERSION_GTK3 gtk3_wm_macros                      ||
   ! PKG_CONFIG_FOR_BUILD="$(host_pkg_config)"                        \
     build_component  gtk3                                            \
     "--with-included-immodules"                                      ||
   ! free_component   gtk+        $VERSION_GTK3 "gtk3"                ||
   ! unpack_component libcroco                                        ||
   ! build_component  libcroco                                        ||
   ! free_component   libcroco    $VERSION_CROCO   "libcroco"         ||
   ! unpack_component librsvg                                         ||
   ! build_component  librsvg     "--disable-introspection"           ||
   ! free_component   librsvg     $VERSION_RSVG    "librsvg"          ||
   ! unpack_component gtk-engines                                     ||
   ! build_component  gtk-engines                                     ||
   ! free_component   gtk-engines $VERSION_GTK_ENG "gtk-engines"      ||
   ! unpack_component hicolor-icon-theme                              ||
   ! build_component  hicolor-icon-theme                              ||
   ! free_component   hicolor-icon-theme $VERSION_HICOLOR             \
     "hicolor-icon-theme"                                             ||
   ! unpack_component tango-icon-theme                                ||
   ! patch_src tango-icon-theme $VERSION_TANGO_ICONS                  \
     "tango_pkg_config_host"                                          ||
   ! PKG_CONFIG_FOR_BUILD="$(host_pkg_config)"                        \
     build_component  tango-icon-theme   $VERSION_TANGO_ICONS         ||
   ! free_component   tango-icon-theme   $VERSION_TANGO_ICONS         \
     "tango-icon-theme"                                               ||
   ! unpack_component adwaita-icon-theme                              ||
   ! build_component  adwaita-icon-theme                              ||
   ! free_component   adwaita-icon-theme $VERSION_ADWAITA_ICON        \
     "adwaita-icon-theme"                                             ||
   ! unpack_component gnome-icon-theme                                ||
   ! patch_src gnome-icon-theme $VERSION_GNOME_ICONS \
     "gnomeitheme-build-pkgconfig"                                    ||
   ! PKG_CONFIG_FOR_BUILD="$(host_pkg_config)"                        \
     build_component  gnome-icon-theme                                ||
   ! free_component   gnome-icon-theme $VERSION_GNOME_ICONS           \
     "gnome-icon-theme"                                               ||
   ! unpack_component gnome-icon-theme-extras                         ||
   ! patch_src gnome-icon-theme-extras $VERSION_GNOME_ICONE \
     "gnomeitheme-build-pkgconfig"                                    ||
   ! PKG_CONFIG_FOR_BUILD="$(host_pkg_config)"                        \
     build_component  gnome-icon-theme-extras                         ||
   ! free_component   gnome-icon-theme-extras $VERSION_GNOME_ICONE    \
     "gnome-icon-theme-extras"                                        ||
   ! unpack_component gnome-themes-standard                           ||
   ! build_component  gnome-themes-standard                           ||
   ! free_component   gnome-themes-standard $VERSION_GNOME_THEME_STD  \
     "gnome-themes-standard"
then
  log_error "gtk+ stack build failed"
  exit 1
fi
fi

if test "x$CROSSER_GTK4" = "xyes" ; then
if ! unpack_component  graphene                                       ||
   ! patch_src         graphene   $VERSION_GRAPHENE graphene_epsilon  ||
   ! ( is_smaller_version $VERSION_GRAPHENE 1.5.4 ||
       patch_src graphene $VERSION_GRAPHENE graphene_aligned_malloc)  ||
   ! build_component   graphene                                       ||
   ! free_component    graphene   $VERSION_GRAPHENE "graphene"        ||
   ! unpack_component  libxkbcommon                                     ||
   ! patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_strndup"      ||
   ! (test "x$CROSSER_SETUP" != "xwin64" ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_longlongcast" ) ||
   ! build_component   libxkbcommon  "--disable-x11"                    ||
   ! free_component    libxkbcommon  $VERSION_XKBCOMMON "libxkbcommon"  ||
   ! unpack_component  gtk4                                           ||
   ! patch_src gtk+ $VERSION_GTK4 "gtk4_winnt"                        ||
   ! patch_src gtk+ $VERSION_GTK4 "gtk4_func_prototype"               ||
   ! (is_minimum_version $VERSION_GTK4 3.92.0 ||
      patch_src gtk+ $VERSION_GTK4 "gtk4_demoless" )                  ||
   ! (is_minimum_version $VERSION_GTK4 3.92.0 ||
      build_component   gtk4                                          \
      "--with-included-immodules" )                                   ||
   ! (is_smaller_version $VERSION_GTK4 3.92.0 ||
      build_with_meson gtk4 gtk4 \
      "-D enable-x11-backend=false -D enable-wayland-backend=false -D enable-win32-backend=true -D introspection=false -D with-included-immodules=all" ) ||
   ! free_component    gtk+       $VERSION_GTK4 "gtk4"
then
  log_error "gtk4 chain build failed"
  exit 1
fi
fi

if ! unpack_component  libogg                                         ||
   ! build_component   libogg                                         ||
   ! free_component    libogg     $VERSION_OGG "libogg"               ||
   ! unpack_component  libvorbis                                      ||
   ! build_component   libvorbis                                      ||
   ! free_component    libvorbis  $VERSION_VORBIS "libvorbis"
then
  log_error "Audio stack build failed"
  exit 1
fi

if test "x$CROSSER_SDL" = "xyes" ; then
if ! unpack_component  SDL                                            ||
   ! build_component   SDL                                            ||
   ! free_component    SDL        $VERSION_SDL "SDL"                  ||
   ! rm "$DLLSPREFIX/lib/libSDLmain.la"                               ||
   ! unpack_component  SDL_image                                      ||
   ! build_component   SDL_image                                      ||
   ! free_component    SDL_image  $VERSION_SDL_IMAGE "SDL_image"      ||
   ! unpack_component  SDL_gfx                                        ||
   ! build_component   SDL_gfx                                        ||
   ! free_component    SDL_gfx    $VERSION_SDL_GFX   "SDL_gfx"        ||
   ! unpack_component  SDL_ttf                                        ||
   ! patch_src SDL_ttf $VERSION_SDL_TTF "sdlttf_fttool"               ||
   ! FREETYPE_CONFIG="$DLLSPREFIX/bin/freetype-config"                \
     build_component   SDL_ttf                                        ||
   ! free_component    SDL_ttf    $VERSION_SDL_TTF   "SDL_ttf"        ||
   ! unpack_component  SDL_mixer                                      ||
   ! patch_src SDL_mixer $VERSION_SDL_MIXER SDLmixer_configmacrodir   ||
   ! patch_src SDL_mixer $VERSION_SDL_MIXER SDLmixer_host             ||
   ! patch_src SDL_mixer $VERSION_SDL_MIXER SDLmixer_libwindres       ||
   ! patch_src SDL_mixer $VERSION_SDL_MIXER SDLmixer_staticpc         ||
   ! autogen_component SDL_mixer  $VERSION_SDL_MIXER                  \
     "libtoolize aclocal autoconf"                                    ||
   ! build_component   SDL_mixer                                      \
     "--disable-music-mod --disable-music-ogg-shared --disable-music-midi --disable-music-mp3" ||
   ! free_component    SDL_mixer  $VERSION_SDL_MIXER "SDL_mixer"
then
    log_error "SDL stack build failed"
    exit 1
fi
fi

if test "x$CROSSER_SDL2" = "xyes" ; then
if ! unpack_component  SDL2                                           ||
   ! patch_src SDL2 $VERSION_SDL2 "sdl2_epsilon"                      ||
   ! ( ! cmp_versions $VERSION_SDL2 2.0.4 ||
       ( patch_src SDL2 $VERSION_SDL2 "sdl2_writeopen_FUNC_-2.0.4" &&
         patch_src SDL2 $VERSION_SDL2 "sdl2_iiddefs-2.0.4" ))         ||
   ! build_component   SDL2                                           ||
   ! free_component    SDL2       $VERSION_SDL2 "SDL2"                ||
   ! unpack_component  SDL2_image                                     ||
   ! build_component   SDL2_image                                     ||
   ! free_component    SDL2_image $VERSION_SDL2_IMAGE "SDL2_image"    ||
   ! unpack_component  SDL2_gfx                                       ||
   ! autogen_component SDL2_gfx   $VERSION_SDL2_GFX \
        "aclocal automake autoconf"                                   ||
   ! build_component   SDL2_gfx                                       ||
   ! free_component    SDL2_gfx   $VERSION_SDL2_GFX   "SDL2_gfx"      ||
   ! unpack_component  SDL2_ttf                                       ||
   ! touch $CROSSER_SRCDIR/SDL2_ttf-${VERSION_SDL2_TTF}/NEWS          ||
   ! touch $CROSSER_SRCDIR/SDL2_ttf-${VERSION_SDL2_TTF}/README        ||
   ! touch $CROSSER_SRCDIR/SDL2_ttf-${VERSION_SDL2_TTF}/AUTHORS       ||
   ! touch $CROSSER_SRCDIR/SDL2_ttf-${VERSION_SDL2_TTF}/ChangeLog     ||
   ! autogen_component SDL2_ttf   $VERSION_SDL2_TTF \
        "aclocal automake autoconf"                                   ||
   ! build_component   SDL2_ttf                                       \
     "--with-freetype-exec-prefix=$DLLSPREFIX"                        ||
   ! free_component    SDL2_ttf   $VERSION_SDL2_TTF   "SDL2_ttf"      ||
   ! unpack_component  SDL2_mixer                                     ||
   ! build_component   SDL2_mixer                                     ||
   ! free_component    SDL2_mixer $VERSION_SDL2_MIXER "SDL2_mixer"
then
  log_error "SDL2 stack build failed"
  exit 1
fi
fi

if test "x$CROSSER_SFML" = "xyes" ; then
if ! unpack_component     ffmpeg                                                ||
   ! build_component_full ffmpeg ffmpeg                                         \
     "--cross-prefix=$CROSSER_TARGET- --target-os=win32 --arch=$TARGET_ARCH --disable-yasm"    \
     "custom"                                                                   ||
   ! free_component       ffmpeg $VERSION_FFMPEG "ffmpeg"                       ||     
   ! unpack_component     openal-soft                                           ||
   ! SDL2DIR="$DLLSPREFIX" build_component      openal-soft                     ||
   ! free_component       openal-soft $VERSION_OPENAL "openal-soft"             ||     
   ! unpack_component     sfml "" "SFML-${VERSION_SFML}-sources"                ||
   ! build_component_full sfml sfml "" "" "SFML-${VERSION_SFML}"                ||
   ! free_component       "SFML-${VERSION_SFML}" "" "sfml"
then
    log_error "SFML stack build failed"
    exit 1
fi
fi

if test "x$CROSSER_QT" = "xyes"
then
if is_smaller_version $VERSION_QT 5.7.0-beta
then
  CROSSER_QT_EXTRA_CONF="-no-gtkstyle"
else
  CROSSER_QT_EXTRA_CONF=""
fi
if ! unpack_component qt-everywhere-opensource-src                                ||
   ! ( is_minimum_version $VERSION_QT 5.8.0 ||
       ( patch_src qt-everywhere-opensource-src $VERSION_QT "qt_pkgconfig" &&
         patch_src qt-everywhere-opensource-src $VERSION_QT "qt_freetype_libs" )) ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_sharappidinfolink"    ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_g++"                  ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_disableidc-5.4.2"     ||
   ! (( is_smaller_version $VERSION_QT 5.9.0 &&
        patch_src qt-everywhere-opensource-src $VERSION_QT "qt_linkflags" ) ||
      ( is_minimum_version $VERSION_QT 5.9.0 &&
        patch_src qt-everywhere-opensource-src $VERSION_QT "qt_linkflags-5.9" ))  ||
   ! ( is_smaller_version $VERSION_QT 5.6.0 ||
       is_minimum_version $VERSION_QT 5.6.1 ||
       patch_src qt-everywhere-opensource-src $VERSION_QT "qt_evrinclude" )       ||
   ! ( is_smaller_version $VERSION_QT 5.7.0 ||
       is_minimum_version $VERSION_QT 5.8.0 ||
       patch_src qt-everywhere-opensource-src $VERSION_QT "qt_vkbdquick" )        ||
   ! ( is_smaller_version $VERSION_QT 5.8.0 ||
       patch_src qt-everywhere-opensource-src $VERSION_QT "qt_vs_interop" )       ||
   ! ( is_smaller_version $VERSION_QT 5.9.0 ||
       is_minimum_version $VERSION_QT 5.9.2 ||
       patch_src qt-everywhere-opensource-src $VERSION_QT "qt_mapbox_disable" )   ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_dllsprefix"           ||
   ! SOURCE_ROOT_CROSSER_HACK="$CROSSER_SRCDIR/$(src_subdir qt-everywhere-opensource-src $VERSION_QT)/qtwebkit/Source/WebCore"  \
     build_component_full  qt-everywhere-opensource-src                                    \
     qt-everywhere-opensource-src                                                          \
     "-opensource -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=${CROSSER_TARGET}- -device-option DLLSPREFIX=${DLLSPREFIX} -nomake examples -no-opengl -system-pcre $CROSSER_QT_EXTRA_CONF" \
     "qt" "" "no"                                                                 ||
   ! free_component   qt-everywhere-opensource-src $VERSION_QT "qt-everywhere-opensource-src"
then
  log_error "QT stack build failed"
  exit 1
fi
fi

GDKPBL="lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
WGDKPBL="$(echo $GDKPBL | sed 's,/,\\,g')"

log_write 1 "Creating crosser.txt"
(
  echo "Dllstack"
  echo "========================="
  echo "Version=\"$CROSSER_VERSION\""
  echo "FeatureLevel=\"$CROSSER_FEATURE_LEVEL\""
  echo "Setup=\"$CROSSER_SETUP\""
  echo "Set=\"$CROSSER_VERSIONSET\""
  echo "Built=\"$(date +"%d.%m.%Y")\""
  echo "-------------------------"
  if test "x$VERSION_GTK3" != "x0"
  then
    echo "CROSSER_GTK3=\"yes\""
  else
    echo "CROSSER_GTK3=\"no\""
  fi
  echo "CROSSER_GTK4=\"$CROSSER_GTK4\""
  echo "CROSSER_QT=\"$CROSSER_QT\""
  echo "CROSSER_SDL2=\"$CROSSER_SDL2\""
  echo "CROSSER_READLINE=\"$CROSSER_READLINE\""
  echo "CROSSER_SFML=\"$CROSSER_SFML\""
  echo
  echo "; Scheduled for complete removal"
  echo "-------------------------"
  echo "CROSSER_SDL=\"$CROSSER_SDL\""
  if test "x$VERSION_GTK2" != "x0"
  then
    echo "CROSSER_GTK2=\"yes\""
  else
    echo "CROSSER_GTK2=\"no\""
  fi
  echo
  echo "; Already removed"
  echo "-------------------------"
  echo "CROSSER_EXPAT=\"no\""
) > "$DLLSPREFIX/crosser.txt"

log_write 1 "Creating configuration files"

if test "x$VERSION_GTK3" != "x0"
then
  mkdir -p "$DLLSPREFIX/etc/gtk-3.0"
  (
    echo -n -e "[Settings]\r\n"
    echo -n -e "gtk-fallback-icon-theme = gnome\r\n"
    echo -n -e "gtk-button-images = true\r\n"
    echo -n -e "gtk-menu-images = true\r\n"
  ) > "$DLLSPREFIX/etc/gtk-3.0/settings.ini"
fi

if test "x$VERSION_GTK2" != "x0"
then
  mkdir -p "$DLLSPREFIX/etc/gtk-2.0"
  (
    echo -n -e "gtk-icon-theme-name = gnome\r\n"
  ) > "$DLLSPREFIX/etc/gtk-2.0/gtkrc"
fi

log_write 1 "Creating setup.bat"
(
  if test "x$VERSION_PANGO" != "x0" && is_smaller_version $VERSION_PANGO 1.37.0
  then
    echo -n -e "if not exist etc\\\pango mkdir etc\\\pango\r\n"  
    echo -n -e "bin\\\pango-querymodules.exe > etc\\\pango\\\pango.modules\r\n"
  fi
  if test "x$VERSION_GDK_PIXBUF" != "x0"
  then
      echo -n -e "bin\\\gdk-pixbuf-query-loaders.exe > $WGDKPBL\r\n"
  fi
  if test "x$VERSION_GTK3" != "x0"
  then
      echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\Adwaita\r\n"
      echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\gnome\r\n"
      echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\hicolor\r\n"
  fi
  echo -n -e "if not exist etc\\\crosser mkdir etc\\\crosser\r\n"
  echo -n -e "echo done > etc\\\crosser\\\setup.state\r\n"
) > "$DLLSPREFIX/setup.bat"

log_write 1 "Creating launch.bat"
(
  echo -n -e "set WINSTACK_ROOT=%~dp0\r\n"
  echo -n -e "set PATH=%~dp0\\\lib;%~dp0\\\bin;%PATH%\r\n"
  if test "x$CROSSER_QT" = "xyes"
  then
      echo -n -e "set QT_PLUGIN_PATH=%~dp0\\\plugins\r\n"
  fi
) > "$DLLSPREFIX/launch.bat"

log_write 1 "IMPORTANT: Remember to run setup.bat when installing to target"

log_write 1 "SUCCESS"
