#!/bin/bash

# dllstack.sh: Cross-compile set of libraries for Windows target.
#
# (c) 2008-2021 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

#############################################################################################
#
# Preparations
#

CROSSER_MAINDIR="$(cd "$(dirname "$0")" ; pwd)"

if ! test -e "$CROSSER_MAINDIR/CrosserVersion" && test -e "/usr/share/crosser/CrosserVersion"
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

# $1 - Component
# $2 - Extra configure options
build_component_def_make()
{
  build_component_full "$1" "$1" "$2" "" "" "" "" "yes"
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
# [$8] - 'yes' - build default target before 'install'
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

  BNAME=$(component_name_to_package_name $2 $BVER)

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
    export PKG_CONFIG_PATH="$NATIVE_PREFIX/lib/$CROSSER_PKG_ARCH/pkgconfig:$NATIVE_PREFIX/lib64/pkgconfig"
  elif test "x$4" = "xcross"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX --build=$CROSSER_BUILD_ARCH --host=$CROSSER_BUILD_ARCH --target=$CROSSER_TARGET $3"
    unset CPPFLAGS
    unset LDFLAGS
    export PKG_CONFIG_PATH="$NATIVE_PREFIX/lib/$CROSSER_PKG_ARCH/pkgconfig:$NATIVE_PREFIX/lib64/pkgconfig"
  elif test "x$4" = "xpkg-config"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX --program-prefix=$CROSSER_TARGET- $3"
    unset CPPFLAGS
    unset LDFLAGS
    export PKG_CONFIG_PATH="$NATIVE_PREFIX/lib/$CROSSER_PKG_ARCH/pkgconfig:$NATIVE_PREFIX/lib64/pkgconfig"
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
    export PKG_CONFIG_PATH="$DLLSPREFIX/lib/$CROSSER_PKG_ARCH/pkgconfig"
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
    if test -f "$SRCDIR/XCompile.txt"
    then
      # openal-soft uses this
      cmake -DCMAKE_TOOLCHAIN_FILE="$SRCDIR/XCompile.txt" -DCMAKE_SYSTEM_NAME="Windows" -DHOST=$CROSSER_TARGET -DCMAKE_INSTALL_PREFIX="${DLLSPREFIX}" "$SRCDIR" >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log
    else
      cmake -DCMAKE_SYSTEM_NAME="Windows" -DHOST=$CROSSER_TARGET -DCMAKE_INSTALL_PREFIX="${DLLSPREFIX}" "$SRCDIR" >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log
    fi
  fi

  log_write 1 "Building $DISPLAY_NAME"

  if test -f Makefile
  then
    if test "x$8" = "xyes"
    then
      log_write 3 "  Make targets: [default] install"
    else
      log_write 3 "  Make targets: install"
    fi
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

    if test "x$8" = "xyes"
    then
      if ! make $MAKEOPTIONS >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
      then
        log_error "Make for $DISPLAY_NAME failed"
        return 1
      fi
    fi

    if ! make $MAKEOPTIONS install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
    then
      log_error "Install for $DISPLAY_NAME failed"
      return 1
    fi
  elif test -f CMakeCache.txt
  then
    if ! cmake --build . --parallel >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
    then
      log_error "CMake build for $DISPLAY_NAME failed"
      return 1
    fi
    if ! cmake --install . >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
    then
      log_error "CMake install for $DISPLAY_NAME failed"
      return 1
    fi
  else
    log_error "Can't detect build method for $DISPLAY_NAME"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "$DISPLAY_NAME : $BVER" >> $DLLSPREFIX/ComponentVersions.txt
  fi

  return $RET
}

# $1 - Component
# $2 - Extra meson options
build_with_meson()
{
  build_with_meson_full "$1" "$1" "$2"
}

# $1 - Component
# $2 - Extra meson options
build_with_meson_host()
{
  build_with_meson_full "native-$1" "$1" "$2" "native"
}

# $1 - Build dir
# $2 - Component
# $3 - Extra meson options
# [$4] - Build type ('native' | 'cross')
# [$5] - Source subdir
build_with_meson_full()
{
  log_packet "$2"

  BVER=$(component_version $2)

  if test "x$BVER" = "x"
  then
    log_error "Version for $2 not defined"
    return 1
  fi

  if test "x$BVER" = "x0"
  then
    return 0
  fi

  BNAME=$(component_name_to_package_name $2 $BVER)

  SUBDIR="$(src_subdir $BNAME $BVER)"
  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $BNAME version $BVER"
    return 1
  fi
  if test "x$5" != "x" ; then
    SUBDIR="$SUBDIR/$5"
    if ! test -d "$CROSSER_SRCDIR/$SUBDIR" ; then
      log_error "Cannot find source subdir \"$SUBDIR\""
      return 1
    fi
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

  if test "x$4" = "xnative" ; then
    export PKG_CONFIG_PATH="$NATIVE_PREFIX/lib/$CROSSER_PKG_ARCH/pkgconfig:$NATIVE_PREFIX/lib64/pkgconfig"
  else
    export CPPFLAGS="-I$DLLSPREFIX/include -I$TGT_HEADERS $CROSSER_WINVER_FLAG"
    export LDFLAGS="-L$DLLSPREFIX/lib -static-libgcc $CROSSER_STDCXX"
    export PKG_CONFIG_PATH="$DLLSPREFIX/lib/$CROSSER_PKG_ARCH/pkgconfig"
  fi

  log_write 1 "Running meson for $DISPLAY_NAME"
  log_write 3 "  Options: $3"

  if test "x$4" = "xnative"
  then
    if ! meson.py $SRCDIR . --prefix=$NATIVE_PREFIX $3 \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
    then
      log_error "Meson for $DISPLAY_NAME failed"
      return 1
    fi
  elif ! meson.py $SRCDIR . --cross-file $DLLSPREFIX/etc/meson_cross_file.txt \
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

  if ! cp "$DLLSPREFIX/lib/libz.dll"* "$DLLSPREFIX/bin/"
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

  if is_minimum_version $VERSION_PDCURSES 3.6
  then
    SUBDIR=$SUBDIR/wincon
    MKFILE=Makefile
  else
    SUBDIR=$SUBDIR/win32
    MKFILE=mingwin32.mak
  fi

  (
  if ! cd "$CROSSER_SRCDIR/$SUBDIR"
  then
    log_error "Cannot change to directory $CROSSER_SRCDIR/$SUBDIR"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default]"
  log_write 4 "  Options: \"$CROSSER_COREOPTIONS\""

  if ! make -f $MKFILE $CROSSER_COREOPTIONS \
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
CROSSER_PKG_ARCH="$(echo $CROSSER_BUILD_ARCH | sed 's/-pc//')"

if ! test -e "$CROSSER_MAINDIR/setups/$CROSSER_SETUP.conf" ; then
  log_error "Can't find setup \"$CROSSER_SETUP.conf\""
  exit 1
fi
. "$CROSSER_MAINDIR/setups/$CROSSER_SETUP.conf"

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

export PATH="$NATIVE_PREFIX/bin:$NATIVE_PREFIX/meson-$VERSION_MESON:$PATH"

if ! packetdir_check
then
  log_error "Packetdir missing"
  exit 1
fi

log_write 1 "Creating meson cross file"

(
  TARGET_GCC=$(command -v $CROSSER_TARGET-gcc)
  TARGET_GPP=$(command -v $CROSSER_TARGET-g++)
  TARGET_AR=$(command -v $CROSSER_TARGET-ar)
  TARGET_STRIP=$(command -v $CROSSER_TARGET-strip)
  TARGET_PKGCONFIG=$NATIVE_PREFIX/bin/$CROSSER_TARGET-pkg-config
  TARGET_WINDRES=$(command -v $CROSSER_TARGET-windres)

  if test "x$TARGET_GCC" = "x"   ||
     test "x$TARGET_GPP" = "x"   ||
     test "x$TARGET_AR" = "x"    ||
     test "x$TARGET_STRIP" = "x" ||
     test "x$TARGET_WINDRES" = "x"
  then
    log_error "Cross-tools missing"
    exit 1
  fi
  if ! sed -e "s,<TARGET_GCC>,$TARGET_GCC,g" \
           -e "s,<TARGET_GPP>,$TARGET_GPP,g" \
           -e "s,<TARGET_AR>,$TARGET_AR,g" \
           -e "s,<TARGET_STRIP>,$TARGET_STRIP,g" \
           -e "s,<TARGET_PKGCONFIG>,$TARGET_PKGCONFIG,g" \
           -e "s,<TARGET_WINDRES>,$TARGET_WINDRES,g" \
           $CROSSER_MAINDIR/scripts/$MESON_CROSS_FILE \
           > $DLLSPREFIX/etc/meson_cross_file.txt
  then
    log_error "Meson cross-file creation failed"
    exit 1
  fi
)

log_write 1 "Creating cmake toolchain file"

(
  TARGET_GCC=$(command -v $CROSSER_TARGET-gcc)
  TARGET_GPP=$(command -v $CROSSER_TARGET-g++)

  if test "x$TARGET_GCC" = "x"   ||
     test "x$TARGET_GPP" = "x"
  then
    log_error "Cross-tools missing"
    exit 1
  fi
  if ! sed -e "s,<TARGET_GCC>,$TARGET_GCC,g" \
           -e "s,<TARGET_GPP>,$TARGET_GPP,g" \
           $CROSSER_MAINDIR/scripts/$CMAKE_PLATFORM_FILE \
           > $DLLSPREFIX/etc/toolchain.cmake
  then
    log_error "CMake toolchain file creation failed"
    exit 1
  fi
)

log_write 1 "Setting up fixed environment"

if ! mkdir -p "$DLLSPREFIX/lib/$CROSSER_PKG_ARCH" ||
   ! ln -s ../pkgconfig "$DLLSPREFIX/lib/$CROSSER_PKG_ARCH/"
then
  log_error "Failed to set up fixed environment"
  exit 1
fi

if test "x$CROSSER_DOWNLOAD" = "xyes"
then
    steplist="win"
    if test "x$CROSSER_SDL2" = "xyes" ; then
        steplist="${steplist},sdl2"
    fi
    if test "x$CROSSER_SFML" = "xyes" ; then
        steplist="${steplist},sfml"
    fi
    if test "x$CROSSER_FULL" = "xyes" ; then
        steplist="${steplist},full"
    fi
    if ! (cd "$CROSSER_PACKETDIR" &&
          "$CROSSER_MAINDIR/scripts/download_packets.sh" "$steplist" "$CROSSER_VERSIONSET" "$CROSSER_SETUP")
  then
    log_error "Downloading packets failed"
    exit 1
  fi
fi

GETTEXT_VARS="$(read_configure_vars gettext)"
IM_VARS="$(read_configure_vars imagemagick)"
CAIRO_VARS="$(read_configure_vars cairo)"
ICU_FILEVER="$(icu_filever $VERSION_ICU)"

export LD_LIBRARY_PATH="${NATIVE_PREFIX}/lib:${NATIVE_PREFIX}/lib/$CROSSER_PKG_ARCH"

if ! unpack_component     meson "" "meson/${VERSION_MESON}"              ||
   ! cp -R "$CROSSER_SRCDIR/meson-$VERSION_MESON" "$NATIVE_PREFIX"       ||
   ! unpack_component     autoconf                          ||
   ! build_component_host autoconf                          ||
   ! free_component       autoconf   $VERSION_AUTOCONF "native-autoconf" ||
   ! unpack_component     automake                          ||
   ! build_component_host automake                          ||
   ! free_component       automake   $VERSION_AUTOMAKE "native-automake" ||
   ! unpack_component     libtool                           ||
   ! build_component_full native-libtool libtool            \
     "" "native" "" "" "$VERSION_LIBTOOL"                   ||
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
   ! build_with_meson_host glib "-D libmount=disabled -D selinux=disabled"  ||
   ! free_build           "native-glib"                                     ||
   ! unpack_component     gtk-doc                                           ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_pc"                         ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_configheaders"              ||
   ! autogen_component    gtk-doc $VERSION_GTK_DOC                          ||
   ! build_component_host gtk-doc                                           ||
   ! free_component  gtk-doc   $VERSION_GTK_DOC                             \
     "native-gtk-doc"                                                       ||
   ! unpack_component     gobject-introspection                             ||
   ! build_with_meson_host gobject-introspection                            ||
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
   ! (is_smaller_version $VERSION_ICU 59.1 ||
      patch_src icu $VERSION_ICU icu_filetools_inc )                        ||
   ! CXX="g++" CFLAGS="-fPIC" build_component_full native-icu4c icu4c ""    \
     "native" "icu/source" "" "" "yes"                                      ||
   ! unpack_component tiff                                                  ||
   ! build_component_host tiff                                              ||
   ! free_build           "native-tiff"                                     ||
   ! unpack_component     libxml2                                           ||
   ! build_component_host libxml2 "--without-python"                        ||
   ! free_build           "native-libxml2"                                  ||
   ! unpack_component  shared-mime-info                                     ||
   ! ln -s "../lib/pkgconfig" "$NATIVE_PREFIX/share/pkgconfig"              ||
   ! (is_smaller_version $VERSION_SHARED_MIME_INFO 2.0 ||
      build_with_meson_host shared-mime-info )                              ||
   ! (is_minimum_version $VERSION_SHARED_MIME_INFO 2.0 ||
      build_component_full native-shared-mime-info shared-mime-info \
      "" "native" "" "no" )                                                 ||
   ! free_build           "native-shared-mime-info"                         ||
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
   ! build_component_host ImageMagick "--without-utilities"                 ||
   ! free_build           "native-ImageMagick"
then
  log_error "Native build failed"
  exit 1
fi

SQL_VERSTR="$(sqlite_verstr $VERSION_SQLITE)"
READLINE_VARS="$(read_configure_vars readline)"

if ! build_component_full libtool libtool "" "" "" ""                 \
     "${VERSION_LIBTOOL}"                                             ||
   ! free_component    libtool    $VERSION_LIBTOOL "libtool"          ||
   ! unpack_component  libiconv                                       ||
   ! build_component   libiconv                                       ||
   ! free_component    libiconv   $VERSION_ICONV "libiconv"           ||
   ! unpack_component  zlib                                           ||
   ! patch_src zlib $VERSION_ZLIB zlib_seeko-1.2.6-2                  ||
   ! patch_src zlib $VERSION_ZLIB zlib_nolibc-1.2.6-2                 ||
   ! patch_src zlib $VERSION_ZLIB zlib_dllext                         ||
   ! build_zlib        zlib       $VERSION_ZLIB                       ||
   ! free_component    zlib       $VERSION_ZLIB "zlib"                ||
   ! unpack_component  xz                                             ||
   ! build_component_full xz xz   "--disable-threads" "windres"       ||
   ! free_component    xz         $VERSION_XZ "xz"                    ||
   ! unpack_component  zstd                                           ||
   ! build_with_meson_full zstd zstd "" "" "build/meson"              ||
   ! free_component    zstd       $VERSION_ZSTD "zstd"                ||
   ! unpack_component  curl                                           ||
   ! patch_src curl $VERSION_CURL curl_winpollfd                      ||
   ! build_component   curl                                           \
     "--disable-pthreads --with-schannel"                             ||
   ! free_component    curl       $VERSION_CURL "curl"                ||
   ! unpack_component  sqlite                                                        \
     "" "sqlite-autoconf-${SQL_VERSTR}"                                              ||
   ! build_component_full sqlite sqlite                                              \
     "--disable-threadsafe" "" "sqlite-autoconf-${SQL_VERSTR}"                       ||
   ! free_component    sqlite-autoconf $SQL_VERSTR "sqlite"                          ||
   ! unpack_component  tinycthread "" "tinycthread/v${VERSION_TCT}"                  ||
   ! cp ${CROSSER_MAINDIR}/patch/tct/Makefile.am                                     \
        ${CROSSER_SRCDIR}/tinycthread-${VERSION_TCT}/source/                         ||
   ! cp ${CROSSER_MAINDIR}/patch/tct/configure.ac                                    \
        ${CROSSER_SRCDIR}/tinycthread-${VERSION_TCT}/source/                         ||
   ! ( cd ${CROSSER_SRCDIR}/tinycthread-${VERSION_TCT}/source &&
       aclocal && autoconf && automake --add-missing --foreign )                     \
           >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log                ||
   ! build_component_full tinycthread tinycthread "" ""                              \
     "tinycthread-${VERSION_TCT}/source"                                             ||
   ! free_component    tinycthread $VERSION_TCT "tinycthread"                        ||
   ! (is_smaller_version $VERSION_ICU 64.1 ||
      patch_src icu $VERSION_ICU icu_tct )                                           ||
   ! build_component_full icu4c icu4c                                                \
     "--with-cross-build=$CROSSER_BUILDDIR/native-icu4c" "" "icu/source" "" "" "yes" ||
   ! free_build           "native-icu4c"                                             ||
   ! free_component    icu        $VERSION_ICU "icu4c"                               ||
   ! patch_src ImageMagick $VERSION_IMAGEMAGICK "im_link_ws2_7"                      ||
   ! patch_src ImageMagick $VERSION_IMAGEMAGICK "im_dll_not"                         ||
   ! build_component   ImageMagick                                                   \
     "--without-bzlib --without-threads --without-magick-plus-plus --disable-openmp --without-utilities" ||
   ! free_component    ImageMagick $VERSION_IMAGEMAGICK "ImageMagick"                ||
   ! build_component   libpng                                                        ||
   ! free_component    libpng     $VERSION_PNG "libpng"                              ||
   ! unpack_component  gettext                                                       ||
   ! (is_smaller_version $VERSION_GETTEXT 0.20 ||
      is_minimum_version $VERSION_GETTEXT 0.20.2 ||
      patch_src gettext $VERSION_GETTEXT "gettext_pthread_test_disable" )            ||
   ! LIBS="-liconv" build_component gettext                                          \
     "$GETTEXT_VARS --enable-relocatable --enable-threads=windows --disable-libasprintf --without-emacs"    ||
   ! free_component    gettext    $VERSION_GETTEXT "gettext"                         ||
   ! build_component   pcre                                           \
     "--disable-cpp --enable-unicode-properties"                      ||
   ! free_component    pcre       $VERSION_PCRE    "pcre"             ||
   ! build_component   pcre2                                          \
     "--disable-cpp --enable-unicode-properties --enable-pcre2-16"    ||
   ! free_component    pcre2      $VERSION_PCRE2    "pcre2"           ||
   ! build_component   libffi                                         ||
   ! free_component    libffi     $VERSION_FFI     "libffi"           ||
   ! build_with_meson  glib                                           ||
   ! free_component    glib       $VERSION_GLIB    "glib"             ||
   ! unpack_component  fribidi                                        ||
   ! build_component   fribidi    "--disable-docs"                    ||
   ! free_component    fribidi    $VERSION_FRIBIDI "fribidi"
then
  log_error "Build failed"
  exit 1
fi

if test "x$CROSSER_READLINE" = "xyes" ; then
if ! unpack_component  PDCurses                                          ||
   ! (is_minimum_version $VERSION_PDCURSES 3.6 ||
      patch_src PDCurses $VERSION_PDCURSES "PDCurses_crosswin" )         ||
   ! (is_smaller_version $VERSION_PDCURSES 3.6 ||
      patch_src PDCurses $VERSION_PDCURSES "PDCurses_crosswin-3.6" )     ||
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
   ! (is_smaller_version $VERSION_SHARED_MIME_INFO 2.0 ||
      build_with_meson shared-mime-info )                                   ||
   ! (is_minimum_version $VERSION_SHARED_MIME_INFO 2.0 ||
      build_component_full shared-mime-info shared-mime-info "" "" "" \
       "no" )                                                               ||
   ! free_component    shared-mime-info $VERSION_SHARED_MIME_INFO           \
     "shared-mime-info"                                                     ||
   ! unpack_component  jansson                                              ||
   ! build_component   jansson                                              ||
   ! free_component    jansson    $VERSION_JANSSON "jansson"                ||
   ! unpack_component  freetype                                             ||
   ! build_component   freetype   "--without-bzip2"                         ||
   ! free_component    freetype   $VERSION_FREETYPE "freetype"              ||
   ! unpack_component  harfbuzz "" "harfbuzz/${VERSION_HARFBUZZ}"           ||
   ! ( is_max_version $VERSION_HARFBUZZ 2.5.0 ||
       patch_src harfbuzz $VERSION_HARFBUZZ "harfbuzz_pthread_disable" )    ||
   ! ( is_minimum_version $VERSION_HARFBUZZ 2.6.7 ||
       patch_src       harfbuzz   $VERSION_HARFBUZZ "harfbuzz_python3" )    ||
   ! build_with_meson  harfbuzz   "-Dicu=disabled -Dfontconfig=disabled"    ||
   ! free_component    harfbuzz   $VERSION_HARFBUZZ "harfbuzz"              ||
   ! unpack_component  fontconfig                                           ||
   ! ( is_smaller_version $VERSION_FONTCONFIG 2.12.3 ||
       patch_src       fontconfig $VERSION_FONTCONFIG fontconfig_fcobjs_prototypes ) ||
   ! ( is_smaller_version $VERSION_FONTCONFIG 2.13.0 ||
       patch_src       fontconfig $VERSION_FONTCONFIG fontconfig_disable_test) ||
   ! build_component   fontconfig                                           \
     "--with-freetype-config=$DLLSPREFIX/bin/freetype-config --with-arch=$CROSSER_TARGET --enable-libxml2" ||
   ! free_component    fontconfig $VERSION_FONTCONFIG "fontconfig"          ||
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
   ! patch_src         cairo $VERSION_CAIRO "cairo_fortify_disable"         ||
   ! ( is_minimum_version    $VERSION_CAIRO 1.15.2 ||
       patch_src       cairo $VERSION_CAIRO cairo_1.14.2+ )                 ||
   ! build_component   cairo "$CAIRO_VARS --disable-xlib --enable-win32"    ||
   ! free_component    cairo      $VERSION_CAIRO "cairo"                    ||
   ! unpack_component  pango                                                ||
   ! (is_minimum_version $VERSION_PANGO 1.44 ||
      build_component   pango )                                             ||
   ! (is_smaller_version $VERSION_PANGO 1.44 ||
      is_minimum_version $VERSION_PANGO 1.48 ||
      build_with_meson pango "-Dintrospection=false" )                      ||
   ! (is_smaller_version $VERSION_PANGO 1.48 ||
      build_with_meson pango "-Dintrospection=disabled" )                   ||
   ! free_component    pango      $VERSION_PANGO "pango"                    ||
   ! unpack_component  atk                                                  ||
   ! (is_minimum_version $VERSION_ATK 2.29.1 ||
      build_component   atk )                                               ||
   ! (is_smaller_version $VERSION_ATK 2.29.1 ||
      build_with_meson atk "-D introspection=false" )                       ||
   ! free_component    atk        $VERSION_ATK "atk"
then
  log_error "Build failed"
  exit 1
fi

if test "x$CROSSER_GTK3" = "xno" && test "x$CROSSER_GTK4" != "xyes"
then
  CROSSER_GTK=no
fi

if test "x$CROSSER_GTK" != "xno" ; then
if ! unpack_component     gdk-pixbuf                                  ||
   ! (is_smaller_version $VERSION_GDK_PIXBUF 2.42.0 ||
      build_with_meson gdk-pixbuf \
        "-D relocatable=true -D x11=false -D introspection=disabled" ) ||
   ! (is_smaller_version $VERSION_GDK_PIXBUF 2.38.0 ||
      is_minimum_version $VERSION_GDK_PIXBUF 2.42.0 ||
      build_with_meson gdk-pixbuf \
        "-D relocatable=true -D x11=false -D gir=false" )             ||
   ! (is_minimum_version $VERSION_GDK_PIXBUF 2.38.0 ||
       ( patch_src gdk-pixbuf $VERSION_GDK_PIXBUF gdk_pixbuf_tnrm &&
         build_component  gdk-pixbuf "--enable-relocations" ))        ||
   ! free_component   gdk-pixbuf $VERSION_GDK_PIXBUF "gdk-pixbuf"
then
  log_error "gtk+ stack build failed"
  exit 1
fi

# This is within CROSSER_GTK != xno
if test "x$CROSSER_GTK3" != "xno" ; then
if ! unpack_component gtk3                                            ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gdk/gdkconfig.h         ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gtk/gtk.gresource.xml   ||
   ! ( is_minimum_version $VERSION_GTK3 3.24.14 ||
       patch_src gtk+ $VERSION_GTK3 gtk3_wm_macros )                  ||
   ! ( is_smaller_version $VERSION_GTK3 3.24.14 ||
       patch_src gtk+ $VERSION_GTK3 gtk3_wm_macros-3.24.14 )          ||
   ! ( is_minimum_version $VERSION_GTK3 3.24.16 ||
       patch_src gtk+ $VERSION_GTK3 "gtk3_host_no_install" )          ||
   ! ( is_smaller_version $VERSION_GTK3 3.24.16 ||
       patch_src gtk+ $VERSION_GTK3 "gtk3_host_no_install-3.24.16" )  ||
   ! ( is_smaller_version $VERSION_GTK3 3.24.20 ||
       patch_src gtk+ $VERSION_GTK3 "gtk3_ver_test_disable" )         ||
   ! build_with_meson gtk3                                            \
     "-D enable-x11-backend=false -D enable-wayland-backend=false -D enable-win32-backend=true -D introspection=false"                                                    ||
   ! free_component   gtk+        $VERSION_GTK3 "gtk3"
then
  log_error "gtk+-3 build failed"
  exit 1
fi
fi

# This is within CROSSER_GTK != xno
if ! unpack_component libcroco                                        ||
   ! build_component  libcroco                                        ||
   ! free_component   libcroco    $VERSION_CROCO   "libcroco"         ||
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
   ! patch_src adwaita-icon-theme $VERSION_ADWAITA_ICON               \
     "adwaita_no_host_icon_cache"                                     ||
   ! autogen_component adwaita-icon-theme  $VERSION_ADWAITA_ICON      \
     "aclocal automake"                                               ||
   ! build_component  adwaita-icon-theme                              ||
   ! free_component   adwaita-icon-theme $VERSION_ADWAITA_ICON        \
     "adwaita-icon-theme"
then
  log_error "gtk+ theme stack build failed"
  exit 1
fi
fi

if test "x$CROSSER_GTK" != "xno" && test "x$CROSSER_GTK4" = "xyes" ; then
if ! unpack_component  graphene                                         ||
   ! ( is_minimum_version $VERSION_GRAPHENE 1.10.0 ||
       patch_src graphene $VERSION_GRAPHENE graphene_epsilon )          ||
   ! patch_src graphene $VERSION_GRAPHENE "graphene_infinity_cast"      ||
   ! patch_src graphene $VERSION_GRAPHENE "graphene_nopthread"          ||
   ! (( is_minimum_version $VERSION_GRAPHENE 1.10.6 &&
        build_with_meson graphene "-Dintrospection=disabled" ) ||
      ( is_smaller_version $VERSION_GRAPHENE 1.10.6 &&
        build_with_meson  graphene "-D introspection=false" ))          ||
   ! free_component    graphene   $VERSION_GRAPHENE "graphene"          ||
   ! unpack_component  libxkbcommon                                     ||
   ! (is_minimum_version $VERSION_XKBCOMMON 0.10.0 ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_strndup" )      ||
   ! (test "x$CROSSER_SETUP" != "xwin64" ||
      is_minimum_version $VERSION_XKBCOMMON 0.10.0 ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_longlongcast" ) ||
   ! (is_minimum_version $VERSION_XKBCOMMON 1.1.0 ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_test_opt" )     ||
   ! (is_smaller_version $VERSION_XKBCOMMON 1.2.0 ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_test_opt-1.2" ) ||
   ! (is_smaller_version $VERSION_XKBCOMMON 1.0.0 ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_eof" )          ||
   ! (is_smaller_version $VERSION_XKBCOMMON 1.0.0 ||
      patch_src libxkbcommon $VERSION_XKBCOMMON "xkbcommon_mscver" )       ||
   ! build_with_meson  libxkbcommon                                        \
     "-Denable-x11=false -Denable-wayland=false -Denable-docs=false"       ||
   ! free_component    libxkbcommon  $VERSION_XKBCOMMON "libxkbcommon"     ||
   ! unpack_component  gtk4                                                ||
   ! patch_src gtk  $VERSION_GTK4 "gtk4_winnt"                             ||
   ! patch_src gtk  $VERSION_GTK4 "gtk4_lowercase_windows_h"               ||
   ! (is_minimum_version $VERSION_GTK4 4.4.0 ||
      build_with_meson gtk4 \
        "-D x11-backend=false -D wayland-backend=false -D win32-backend=true -D introspection=disabled -D build-tests=false" ) ||
   ! (is_smaller_version $VERSION_GTK4 4.4.0 ||
      build_with_meson gtk4 \
        "-D x11-backend=false -D wayland-backend=false -D win32-backend=true -D introspection=disabled -D build-tests=false -D media-gstreamer=disabled" ) ||
   ! free_component    gtk        $VERSION_GTK4 "gtk4"
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

if test "x$CROSSER_SDL2" = "xyes" ; then
if ! unpack_component  SDL2                                           ||
   ! patch_src SDL2 $VERSION_SDL2 "sdl2_epsilon"                      ||
   ! build_component_def_make SDL2                                    ||
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
   ! patch_src openal-soft $VERSION_OPENAL "oals_rdynamic_workaround"           ||
   ! patch_src openal-soft $VERSION_OPENAL "oals_inc_check_param"               ||
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

if test "x$CROSSER_QT5" = "xyes"
then
if ! unpack_component qt5                                                    ||
   ! (is_minimum_version $VERSION_QT5 5.14.0 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_g++" )                    ||
   ! (is_smaller_version $VERSION_QT5 5.14.0 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_g++-5.14" )               ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_disableidc-5.4.2"       ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_linkflags-5.11"         ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_vs_interop-5.11"        ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_dllsprefix-5.11"        ||
   ! (is_minimum_version $VERSION_QT5 5.14.0 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_winextras_disable" )      ||
   ! (is_smaller_version $VERSION_QT5 5.14.0 ||
      is_minimum_version $VERSION_QT5 5.14.2 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_winextras_disable-5.14" ) ||
   ! (is_smaller_version $VERSION_QT5 5.14.2 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_winextras_disable-5.14.2" ) ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_yarr_inc_conflict"         ||
   ! (is_smaller_version $VERSION_QT5 5.13 ||
      is_minimum_version $VERSION_QT5 5.14 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_localtime_not_r" )        ||
   ! (is_smaller_version $VERSION_QT5 5.14 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_localtime_not_r-5.14" )   ||
   ! (is_minimum_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_python3" )                ||
   ! (is_smaller_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_python3-5.15" )           ||
   ! (is_smaller_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_test_thread_disable" )    ||
   ! (is_smaller_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_location_disable" )       ||
   ! (is_smaller_version $VERSION_QT5 5.14.0 ||
      is_minimum_version $VERSION_QT5 5.14.2 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_setupapi_case" )          ||
   ! (is_smaller_version $VERSION_QT5 5.14.0 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_quick3d_req_ogl" )        ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_d3d12_disable"             ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_limits_inc"                ||
   ! build_component_full  qt5 qt5                                              \
     "-opensource -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=${CROSSER_TARGET}- -device-option DLLSPREFIX=${DLLSPREFIX} -device-option EXTRA_LIBDIR=$DLLSPREFIX/lib -device-option EXTRA_INCDIR=$DLLSPREFIX/include -nomake examples -no-opengl -no-evr -system-pcre -system-zlib -system-harfbuzz" \
     "qt" "" "" "" "yes"                                                        ||
   ! free_component   qt-everywhere-src $VERSION_QT5 "qt-everywhere-src"
then
  log_error "QT5 stack build failed"
  exit 1
fi
fi

GDKPBL="lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
WGDKPBL="$(echo $GDKPBL | sed 's,/,\\,g')"

log_write 1 "Creating crosser.txt"
(
  echo "# Dllstack"
  echo "# ========================="
  echo "CrosserVersion=\"$CROSSER_VERSION\""
  echo "CrosserFeatureLevel=\"$CROSSER_FEATURE_LEVEL\""
  echo "CrosserSetup=\"$CROSSER_SETUP\""
  echo "CrosserSet=\"$CROSSER_VERSIONSET\""
  echo "CrosserBuilt=\"$(date +"%d.%m.%Y")\""
  echo
  echo "# -------------------------"
  if test "x$VERSION_GTK3" != "x0"
  then
    echo "CROSSER_GTK3=\"yes\""
  else
    echo "CROSSER_GTK3=\"no\""
  fi
  echo "CROSSER_GTK4=\"$CROSSER_GTK4\""
  echo "CROSSER_QT5=\"$CROSSER_QT5\""
  echo "CROSSER_QT6=\"$CROSSER_QT6\""
  echo "CROSSER_SDL2=\"$CROSSER_SDL2\""
  echo "CROSSER_READLINE=\"$CROSSER_READLINE\""
  echo "CROSSER_SFML=\"$CROSSER_SFML\""
  echo
  echo "# Deprecated entries"
  echo "# -------------------------"
  echo "CROSSER_QT=\"$CROSSER_QT5\""
  echo "CROSSER_GTK2=\"no\""
) > "$DLLSPREFIX/crosser.txt"

log_write 1 "Copying license information"
if ! mkdir -p $DLLSPREFIX/license ||
   ! cp $CROSSER_MAINDIR/license/crosser.license $DLLSPREFIX/license/ ||
   ! cp $CROSSER_MAINDIR/COPYING $DLLSPREFIX/license/
then
  log_error "Failed to copy license information"
  exit 1
fi

log_write 1 "Creating configuration files"

if test "x$VERSION_GTK3" != "x0"
then
  mkdir -p "$DLLSPREFIX/etc/gtk-3.0"
  (
    echo -n -e "[Settings]\r\n"
    echo -n -e "gtk-fallback-icon-theme = hicolor\r\n"
    echo -n -e "gtk-button-images = true\r\n"
    echo -n -e "gtk-menu-images = true\r\n"
  ) > "$DLLSPREFIX/etc/gtk-3.0/settings.ini"
fi

log_write 1 "Creating setup.bat"
(
  echo -n -e "bin\\\glib-compile-schemas.exe share\\\glib-2.0\\\schemas\r\n"
  if test "x$VERSION_GDK_PIXBUF" != "x0"
  then
      echo -n -e "bin\\\gdk-pixbuf-query-loaders.exe > $WGDKPBL\r\n"
  fi
  if test "x$VERSION_GTK3" != "x0"
  then
      echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\Adwaita\r\n"
      echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\hicolor\r\n"
  fi
  echo -n -e "if not exist etc\\\crosser mkdir etc\\\crosser\r\n"
  echo -n -e "echo done > etc\\\crosser\\\setup.state\r\n"
) > "$DLLSPREFIX/setup.bat"

log_write 1 "Creating launch.bat"
(
  echo -n -e "set WINSTACK_ROOT=%~dp0\r\n"
  echo -n -e "set PATH=%~dp0\\\lib;%~dp0\\\bin;%PATH%\r\n"
  if test "x$CROSSER_QT5" = "xyes"
  then
      echo -n -e "set QT_PLUGIN_PATH=%~dp0\\\plugins\r\n"
  fi
) > "$DLLSPREFIX/launch.bat"

log_write 1 "IMPORTANT: Remember to run setup.bat when installing to target"

log_write 1 "SUCCESS"
