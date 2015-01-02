#!/bin/bash

# dllstack.sh: Cross-compile set of libraries for Windows target.
#
# (c) 2008-2014 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
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
  VERSIONSET="$2"
else
  VERSIONSET="current"
fi
if test -e "$CROSSER_MAINDIR/setups/$VERSIONSET.versions"
then
  . "$CROSSER_MAINDIR/setups/$VERSIONSET.versions"
else
  # Versions being unset do not prevent loading of setup_reader.sh and helper.sh,
  # resulting environment would just be unusable for building.
  # We are not going to build anything, but just issuing error message - and for
  # that we read log_error from helpers.sh
  ERR_MSG="Cannot find versionset \"$VERSIONSET.versions\""
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
  SETUP="win32"
else
  SETUP="$3"
fi

if ! log_init
then
  echo "Cannot setup logging!" >&2
  exit 1
fi

if test "x$ERR_MSG" != "x"
then
  log_error "$ERR_MSG"
  exit 1
fi

if test "x$1" != "x"
then
  DLLSPREFIX="$1"
fi

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

# $1   - Build dir
# $2   - Component
# $3   - Extra configure options
# [$4] - Build type ('native' | 'windres' | 'cross' | 'qt' | 'pkg-config')
# [$5] - Src subdir 
# [$6] - Make options
# [$7] - Version
build_component_full()
{
  log_packet "$1"

  if test "x$7" != "x"
  then
    BVER="$7"
  else
    BVER="$(component_version $2)"
  fi

  if test "x$BVER" = "x" ; then
    log_error "Version for $2 not defined"
    return 1
  fi

  if test "x$BVER" = "x0"
  then
    return 0
  fi

  if test "x$2" = "xgtk2" || test "x$2" = "xgtk3"
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

  BUILDDIR="$CROSSER_BUILDDIR/$1"
  if ! mkdir -p "$BUILDDIR"
  then
    log_error "Failed to create directory $BUILDDIR"
    return 1
  fi

  (
  cd "$BUILDDIR"
  SRCDIR="$CROSSER_SRCDIR/$SUBDIR"

  if test "x$4" = "xnative"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xcross"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX --build=$BUILD --host=$BUILD --target=$TARGET $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xpkg-config"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX --program-prefix=$TARGET- $3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$4" = "xwindres"
  then
    CONFOPTIONS="--prefix=$DLLSPREFIX --build=$BUILD --host=$TARGET --target=$TARGET $3"
    unset CPPFLAGS
    export LDFLAGS="-L$DLLSPREFIX/lib -static-libgcc $CROSSER_STDCXX"
  elif test "x$4" = "xqt"
  then
    CONFOPTIONS="-prefix $DLLSPREFIX $3"
    export CPPFLAGS="-isystem ${DLLSPREFIX}/include"
    export CFLAGS="${CPPFLAGS}"
    export CXXFLAGS="-isystem ${DLLSPREFIX}/include"
    export LDFLAGS="-L${DLLSPREFIX}/lib -static-libgcc $CROSSER_STDCXX"
  else
    CONFOPTIONS="--prefix=$DLLSPREFIX --build=$BUILD --host=$TARGET --target=$TARGET $3"
    export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS"
    export LDFLAGS="-L$DLLSPREFIX/lib -static-libgcc $CROSSER_STDCXX"
  fi

  if test -x "$SRCDIR/configure"
  then
    log_write 1 "Configuring $1"
    log_write 3 "  Options: \"$CONFOPTIONS\""
    log_flags

    if ! "$SRCDIR/configure" $CONFOPTIONS >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log
    then
      log_error "Configure for $1 failed"
      return 1
    fi
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default] install"
  if test "x$6" = "xno"
  then
    MAKEOPTIONS=""
  elif test "x$6" != "x"
  then
    MAKEOPTIONS="$6"
  else
    MAKEOPTIONS="$CROSSER_MAKEOPTIONS"
  fi
  log_write 4 "  Options: \"$MAKEOPTIONS\""

  if ! make $MAKEOPTIONS >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make $MAKEOPTIONS install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Install for $1 failed"
    return 1
  fi
  )
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

  (
  export CC=$TARGET-gcc
  export RANLIB=$TARGET-ranlib
  export AR=$TARGET-ar

  if ! cd "$CROSSER_SRCDIR/$SUBDIR"
  then
    log_error "Cannot change to directory $CROSSER_SRCDIR/$SUBDIR"
    return 1
  fi

  export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS"
  export LDFLAGS="-L$DLLSPREFIX/lib"

  CONFOPTIONS="--prefix=$DLLSPREFIX --shared $3"

  # TODO: zlib build doesn't like this variable, check why.
  unset TARGET_ARCH

  log_write 1 "Configuring $1"
  log_write 3 "  Options: \"$CONFOPTIONS\""
  log_flags

  if ! ./configure $CONFOPTIONS >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Configure for $1 failed"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default] install"
  log_write 4 "  Options: \"$CROSSER_MAKEOPTIONS\""

  if ! make $CROSSER_MAKEOPTIONS >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make $CROSSER_MAKEOPTIONS install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
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
}

# Build bzip2
#
# $1 - Package name
# $2 - Version
#
build_bzip2()
{
  log_packet "$1"

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

  export CC=$TARGET-gcc
  export RANLIB=$TARGET-ranlib
  export AR=$TARGET-ar
  export PREFIX=$DLLSPREFIX
  export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS"
  export LDFLAGS="-L$DLLSPREFIX/lib"

  log_write 1 "Building $1"
  log_write 3 "  Make targets: libbz2.a bzip2 bzip2recover & install"
  log_write 4 "  Options: \"$CROSSER_MAKEOPTIONS\""
  log_flags

  if ! make $CROSSER_MAKEOPTIONS libbz2.a bzip2 bzip2recover \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make $CROSSER_MAKEOPTIONS install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Install for $1 failed"
    return 1
  fi
  )
}

cd $(dirname $0)

BUILD="$($CROSSER_MAINDIR/scripts/aux/config.guess)"

if ! test -e "$CROSSER_MAINDIR/setups/$SETUP.conf" ; then
  log_error "Can't find setup \"$SETUP.conf\""
  exit 1
fi
. "$CROSSER_MAINDIR/setups/$SETUP.conf"

if test "x$DLLSTACK" = "xno"
then
  log_error "dllstack.sh cannot be used with configuration \"$SETUP\"."
  exit 1
fi

if test "x$TARGET_VENDOR" = "x"
then
  TARGET="$TARGET_ARCH-$TARGET_OS"
else
  TARGET="$TARGET_ARCH-$TARGET_VENDOR-$TARGET_OS"
fi

if test -d "/usr/$TARGET/include"
then
  export TGT_HEADERS="/usr/$TARGET/include"
fi

export LIBC_MODE="none"

if test "x$DLLSHOST_PREFIX" = "x" && test "x$LSHOST_PREFIX" != "x" ; then
  echo "Configuration variable LSHOST_PREFIX is deprecated. Please use DLLSHOST_PREFIX." >&2
  DLLSHOST_PREFIX="$LSHOST_PREFIX"
fi

export DLLSPREFIX=$(setup_prefix_default "$HOME/.crosser/<VERSION>/<VERSIONSET>/<SETUP>/winstack" "$DLLSPREFIX")
export NATIVE_PREFIX=$(setup_prefix_default "$HOME/.crosser/<VERSION>/<VERSIONSET>/dllshost" \
                       "$DLLSHOST_PREFIX")

TARGET_GCC_VER=$($TARGET-gcc -dumpversion | sed 's/-.*//')
TARGET_GXX_VER=$($TARGET-g++ -dumpversion | sed 's/-.*//')

log_write 2 "Install:    \"$DLLSPREFIX\""
log_write 2 "Src:        \"$CROSSER_SRCDIR\""
log_write 2 "Log:        \"$CROSSER_LOGDIR\""
log_write 2 "Build:      \"$CROSSER_BUILDDIR\""
log_write 2 "Setup:      \"$SETUP\""
log_write 2 "Versionset: \"$VERSIONSET\""
log_write 2 "cross-gcc:  $TARGET_GCC_VER"
log_write 2 "cross-g++:  $TARGET_GXX_VER"

CROSSER_STDCXX="-static-libstdc++"

if ! remove_dir "$CROSSER_SRCDIR"    ||
   ! remove_dir "$CROSSER_BUILDDIR"  ||
   ! remove_dir "$DLLSPREFIX"        ||
   ! remove_dir "$NATIVE_PREFIX"
then
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

if ! mkdir -p "$DLLSPREFIX/man/man1"
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

if test "x$CROSSER_DOWNLOAD" = "xyes"
then
  if ! (cd "$PACKETDIR" && "$CROSSER_MAINDIR/scripts/download_packets.sh" "win" "$VERSIONSET" )
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
   ! ( is_minimum_version $VERSION_LIBTOOL 2.4.3 ||
       patch_src libtool $VERSION_LIBTOOL libtool_bash )    ||
   ! build_component_full native-libtool libtool            \
     "" "native" "" "" "$BASEVER_LIBTOOL"                   ||
   ! free_build           "native-libtool"                               ||
   ! unpack_component     libffi                            ||
   ! build_component_host libffi                            ||
   ! free_build           "native-libffi"                   ||
   ! unpack_component     pkg-config                                        ||
   ! (! cmp_versions $VERSION_PKG_CONFIG 0.25 ||
      patch_src pkg-config $VERSION_PKG_CONFIG pkgconfig_ac266)             ||
   ! build_component_host pkg-config                                        \
     "--with-pc-path=$NATIVE_PREFIX/lib/pkgconfig --with-internal-glib"     ||
   ! free_component       "native-pkg-config"                               ||
   ! unpack_component     glib                              ||
   ! (is_smaller_version $VERSION_GLIB 2.34.0 ||
      is_minimum_version $VERSION_GLIB 2.36.0 ||
      patch_src glib $VERSION_GLIB glib_nokill )            ||
   ! (is_smaller_version $VERSION_GLIB 2.36.0 ||
      is_minimum_version $VERSION_GLIB 2.38.0 ||
      ( touch $CROSSER_SRCDIR/glib-$VERSION_GLIB/docs/reference/glib/Makefile.in &&
        touch $CROSSER_SRCDIR/glib-$VERSION_GLIB/docs/reference/gobject/Makefile.in &&
        touch $CROSSER_SRCDIR/glib-$VERSION_GLIB/docs/reference/gio/Makefile.in &&
        touch $CROSSER_SRCDIR/glib-$VERSION_GLIB/docs/reference/gio/gdbus-object-manager-example/Makefile.in )) ||
   ! build_component_host glib                                              ||
   ! free_build           "native-glib"                                     ||
   ! unpack_component     gtk-doc                                           ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_pc"                         ||
   ! build_component_host gtk-doc                                           ||
   ! free_component  gtk-doc   $VERSION_GTK_DOC                             \
     "gtk-doc"                                                              ||
   ! unpack_component     gobject-introspection                             ||
   ! build_component_host gobject-introspection                             ||
   ! free_component  gobject-introspection   $VERSION_GOBJ_INTRO            \
     "gobject-introspection"                                                ||
   ! build_component_host pkg-config                                        \
     "--with-pc-path=$DLLSPREFIX/lib/pkgconfig --disable-host-tool" "pkg-config" ||
   ! free_component       pkg-config $VERSION_PKG_CONFIG "cross-pkg-config" ||
   ! unpack_component  icon-naming-utils                                    ||
   ! patch_src icon-naming-utils $VERSION_ICON_NUTILS "icon-nutils-pc"      ||
   ! build_component_host icon-naming-utils                                 ||
   ! free_component    icon-naming-utils $VERSION_ICON_NUTILS               \
     "native-icon-naming-utils"                                             ||
   ! unpack_component  icu4c         "" "icu4c-$ICU_FILEVER-src"            ||
   ! patch_src icu $VERSION_ICU icu_dbl_mant                                ||
   ! CXX="g++" build_component_full native-icu4c icu4c "" "native" "icu/source"  ||
   ! free_build           "native-icu4c"                                         ||
   ! unpack_component gdk-pixbuf                                            ||
   ! (is_smaller_version $VERSION_GDK_PIXBUF 2.30.0 ||
      is_minimum_version $VERSION_GDK_PIXBUF 2.30.3 ||
      ( patch_src gdk-pixbuf $VERSION_GDK_PIXBUF "gdkpixbuf_randmod_disable" &&
        autogen_component gdk-pixbuf $VERSION_GDK_PIXBUF \
        "aclocal automake autoconf" ))                                      ||
   ! build_component_host gdk-pixbuf                                        ||
   ! free_build           "native-gdk-pixbuf"
then
  log_error "Native build failed"
  exit 1
fi

SQL_VERSTR="$(sqlite_verstr $VERSION_SQLITE)"

if ! build_component_full libtool libtool "" "" "" ""                 \
     "${BASEVER_LIBTOOL}"                                             ||
   ! free_component    libtool    $BASEVER_LIBTOOL "libtool"          ||
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
   ! build_bzip2       bzip2      $VERSION_BZIP2                      ||
   ! free_src          bzip2      $VERSION_BZIP2                      ||
   ! unpack_component  xz                                             ||
   ! build_component_full xz xz   "--disable-threads" "windres"       ||
   ! free_component    xz         $VERSION_XZ "xz"                    ||
   ! unpack_component  curl                                           ||
   ! build_component   curl                                           ||
   ! free_component    curl       $VERSION_CURL "curl"                ||
   ! unpack_component  sqlite                                         \
     "" "sqlite-autoconf-${SQL_VERSTR}"                               ||
   ! build_component_full sqlite sqlite-autoconf                      \
     "--disable-threadsafe" "" "" "" "${SQL_VERSTR}"                  ||
   ! free_component    sqlite-autoconf $SQL_VERSTR "sqlite"           ||
   ! CXX="$TARGET-g++" build_component_full icu4c icu4c               \
     "--with-cross-build=$CROSSER_BUILDDIR/native-icu4c" "" "icu/source" ||
   ! free_component    icu        $VERSION_ICU "icu4c"                   ||
   ! unpack_component  ImageMagick                                    ||
   ! patch_src ImageMagick $VERSION_IMAGEMAGICK "im_pthread"          ||
   ! patch_src ImageMagick $VERSION_IMAGEMAGICK "im_nobin"            ||
   ! build_component   ImageMagick                                    \
     "--without-bzlib --without-threads --without-magick-plus-plus"   ||
   ! free_component    ImageMagick $VERSION_IMAGEMAGICK "ImageMagick" ||
   ! unpack_component  libpng                                         ||
   ! patch_src         libpng     $VERSION_PNG "png_epsilon-1.6.8"    ||
   ! build_component   libpng                                         ||
   ! free_component    libpng     $VERSION_PNG "libpng"               ||
   ! unpack_component  gettext                                        ||
   ! patch_src         gettext    $VERSION_GETTEXT "gettext_nolibintl_inc" ||
   ! LIBS="-liconv" build_component gettext                           \
     "$GETTEXT_VARS --enable-relocatable --enable-threads=windows --disable-libasprintf"    ||
   ! free_component    gettext    $VERSION_GETTEXT "gettext"          ||
   ! build_component   libffi                                         ||
   ! free_component    libffi     $VERSION_FFI    "libffi"            ||
   ! build_component   glib       "$GLIB_VARS --with-threads=win32"   ||
   ! free_component    glib       $VERSION_GLIB "glib"
then
  log_error "Build failed"
  exit 1
fi

if ! unpack_component jpeg  "" "jpegsrc.v${VERSION_JPEG}"             ||
   ! build_component jpeg "--enable-shared"                           ||
   ! free_component jpeg $VERSION_JPEG "jpeg"
then
  log_error "Libjpeg build failed"
  exit 1
fi
CONF_JPEG_GTK="--without-libjasper"

if ! unpack_component tiff                                                  ||
   ! patch_src tiff $VERSION_TIFF tiff_config_headers_395                   ||
   ! ( is_minimum_version $VERSION_TIFF 3.9.0 ||
      autogen_component tiff       $VERSION_TIFF )                          ||
   ! build_component_full tiff tiff "$CONF_JPEG_TIFF"                       ||
   ! free_component    tiff       $VERSION_TIFF "tiff"                      ||
   ! unpack_component  expat                                                ||
   ! build_component   expat                                                ||
   ! free_component    expat      $VERSION_EXPAT "expat"                    ||
   ! unpack_component  libxml2                                              ||
   ! build_component   libxml2    "--without-python"                        ||
   ! free_component    libxml2    $VERSION_XML2 "libxml2"                   ||
   ! unpack_component  freetype                                             ||
   ! (is_smaller_version $VERSION_FREETYPE 2.5.1 ||
      is_greater_version $VERSION_FREETYPE 2.5.2 ||
       (patch_src freetype $VERSION_FREETYPE freetype_pngcheck &&
        autogen_component freetype $VERSION_FREETYPE ))                     ||
   ! build_component   freetype   "--without-bzip2"                         ||
   ! free_component    freetype   $VERSION_FREETYPE "freetype"              ||
   ! unpack_component  fontconfig                                           ||
   ! build_component   fontconfig                                           \
     "--with-freetype-config=$DLLSPREFIX/bin/freetype-config --with-arch=$TARGET" ||
   ! free_component    fontconfig $VERSION_FONTCONFIG "fontconfig"          ||
   ! unpack_component  pixman                                               ||
   ! (is_smaller_version $VERSION_PIXMAN 0.28.0 ||
      patch_src          pixman $VERSION_PIXMAN pixman_epsilon )            ||
   ! build_component   pixman                                               \
     "--disable-gtk"                                                        ||
   ! free_component    pixman     $VERSION_PIXMAN "pixman"                  ||
   ! unpack_component  cairo                                                ||
   ! rm -f "$CROSSER_SRCDIR/cairo-$VERSION_CAIRO/src/cairo-features.h"      ||
   ! ( is_smaller_version $VERSION_CAIRO 1.12.10 ||
       patch_src       cairo $VERSION_CAIRO cairo-1.12.10_epsilon )         ||
   ! ( is_minimum_version $VERSION_CAIRO 1.12.10 ||
       patch_src         cairo $VERSION_CAIRO cairo_epsilon )               ||
   ! ( is_smaller_version $VERSION_CAIRO 1.10.0 ||
       patch_src         cairo $VERSION_CAIRO cairo_ffs )                   ||
   ! build_component   cairo "$CAIRO_VARS --disable-xlib --enable-win32"    ||
   ! free_component    cairo      $VERSION_CAIRO "cairo"                    ||
   ! unpack_component  harfbuzz                                             ||
   ! patch_src harfbuzz $VERSION_HARFBUZZ harfbuzz_cxx_link                 ||
   ! ( is_minimum_version $VERSION_HARFBUZZ 0.9.18 ||
      ( patch_src harfbuzz $VERSION_HARFBUZZ harfbuzz_icu_disable &&
        autogen_component harfbuzz   $VERSION_HARFBUZZ            \
          "aclocal automake autoconf" ))                                    || 
   ! CROSSER_STDCXX="-static -lstdc++ -dynamic"                             \
     build_component   harfbuzz   "--without-icu"                           ||
   ! free_component    harfbuzz   $VERSION_HARFBUZZ "harfbuzz"              ||
   ! unpack_component  pango                                                ||
   ! CXX="$TARGET-g++" build_component pango                                ||
   ! free_component    pango      $VERSION_PANGO "pango"                    ||
   ! unpack_component  atk                                                  ||
   ! ( is_minimum_version $VERSION_ATK     2.8.0  ||
       autogen_component atk        $VERSION_ATK  \
         "libtoolize aclocal automake autoconf" )                           ||
   ! build_component   atk                                                  ||
   ! free_component    atk        $VERSION_ATK "atk"
then
  log_error "Build failed"
  exit 1
fi

if ! build_component  gdk-pixbuf                                      ||
   ! free_component   gdk-pixbuf $VERSION_GDK_PIXBUF "gdk-pixbuf"     ||
   ! unpack_component gtk2                                            ||
   ! build_component  gtk2                                            \
     "--disable-cups --disable-explicit-deps --with-included-immodules $CONF_JPEG_GTK" ||
   ! free_component   gtk+        $VERSION_GTK2 "gtk2"                ||
   ! unpack_component gtk3                                            ||
   ! ( is_minimum_version $VERSION_GTK3 3.10.0 ||
       patch_src        gtk+      $VERSION_GTK3 gtk2_no_initguid )    ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gdk/gdkconfig.h         ||
   ! ( is_smaller_version $VERSION_GTK3 3.8.0 ||
       is_minimum_version $VERSION_GTK3 3.10.0 ||
       ( patch_src gtk+ $VERSION_GTK3 gtk3_nativeuic &&
         patch_src gtk+ $VERSION_GTK3 gtk3_no_buildintl ))            ||
   ! ( is_smaller_version $VERSION_GTK3 3.10.0 ||
       is_minimum_version $VERSION_GTK3 3.14.0 ||
       ( patch_src gtk+ $VERSION_GTK3 gtk3_nogdkdef &&
         patch_src gtk+ $VERSION_GTK3 gtk3_nogtkdef ))                ||
   ! ( is_smaller_version $VERSION_GTK3 3.14.0 ||
       patch_src gtk+ $VERSION_GTK3 gtk3_extstring_cross)             ||
   ! (! cmp_versions $VERSION_GTK3 3.14.5 ||
      patch_src gtk+ $VERSION_GTK3 gtk3_noplug )                      ||
   ! PKG_CONFIG_FOR_BUILD="$(which pkg-config)"                       \
     build_component  gtk3                                            \
     "--enable-gtk2-dependency --with-included-immodules"             ||
   ! free_component   gtk+        $VERSION_GTK3 "gtk3"                ||
   ! unpack_component libcroco                                        ||
   ! build_component  libcroco                                        ||
   ! free_component   libcroco    $VERSION_CROCO   "libcroco"         ||
   ! unpack_component librsvg                                         ||
   ! (is_minimum_version  $VERSION_RSVG 2.40.6 ||
       (patch_src librsvg $VERSION_RSVG "rsvg_giowin" &&
        patch_src librsvg $VERSION_RSVG "rsvg_realpath"))             ||
   ! build_component  librsvg     "--disable-introspection"           ||
   ! free_component   librsvg     $VERSION_RSVG    "librsvg"          ||
   ! unpack_component gtk-engines                                     ||
   ! build_component  gtk-engines                                     ||
   ! free_component   gtk-engines $VERSION_GTK_ENG "gtk-engines"      ||
   ! unpack_component hicolor-icon-theme                              ||
   ! patch_src hicolor-icon-theme $VERSION_HICOLOR "hicolor_blddir"   ||
   ! build_component  hicolor-icon-theme                              ||
   ! free_component   hicolor-icon-theme $VERSION_HICOLOR             ||
   ! unpack_component adwaita-icon-theme                              ||
   ! build_component  adwaita-icon-theme                              ||
   ! free_component   adwaita-icon-theme $VERSION_ADWAITA_ICON        ||
   ! unpack_component gnome-icon-theme                                ||
   ! patch_src gnome-icon-theme $VERSION_GNOME_ICONS \
     "gnomeitheme-build-pkgconfig"                                    ||
   ! PKG_CONFIG_FOR_BUILD="$(which pkg-config)" \
     build_component  gnome-icon-theme                                ||
   ! free_component   gnome-icon-theme $VERSION_GNOME_ICONS           \
     "gnome-icon-theme"                                               ||
   ! unpack_component gnome-icon-theme-extras                         ||
   ! patch_src gnome-icon-theme-extras $VERSION_GNOME_ICONE \
     "gnomeitheme-build-pkgconfig"                                    ||
   ! PKG_CONFIG_FOR_BUILD="$(which pkg-config)" \
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
   ! free_component    SDL_mixer  $VERSION_SDL_MIXER "SDL_mixer"      ||
   ! unpack_component  SDL2                                           ||
   ! patch_src SDL2 $VERSION_SDL2 "sdl2_epsilon"                      ||
   ! patch_src SDL2 $VERSION_SDL2 "sdl2_winapifamily"                 ||
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
   ! build_component   SDL2_ttf                                       \
     "--with-freetype-exec-prefix=$DLLSPREFIX"                        ||
   ! free_component    SDL2_ttf   $VERSION_SDL2_TTF   "SDL2_ttf"      ||
   ! unpack_component  SDL2_mixer                                     ||
   ! build_component   SDL2_mixer                                     ||
   ! free_component    SDL2_mixer $VERSION_SDL2_MIXER "SDL2_mixer"
then
  log_error "SDL stack build failed"
  exit 1
fi

if test "x$CROSSER_QT" = "xyes"
then
if ! unpack_component qt-everywhere-opensource-src                              ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_pkgconfig"          ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_freetype_libs"      ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_sharappidinfolink"  ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_g++"                ||
   ! patch_src qt-everywhere-opensource-src $VERSION_QT "qt_disableidc"         ||
   ! build_component_full  qt-everywhere-opensource-src                         \
     qt-everywhere-opensource-src                                               \
     "-opensource -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=${TARGET}- -system-zlib -nomake examples -force-pkg-config -no-gtkstyle -no-opengl" \
     "qt" "" "no"                                                               ||
   ! free_component   qt-everywhere-opensource-src $VERSION_QT "qt-everywhere-opensource-src"
then
  log_error "QT stack build failed"
  exit 1
fi
fi

if is_minimum_version $VERSION_GDK_PIXBUF 2.22.0
then
  GDKPBL="lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
else
  GDKPBL="etc/gtk-2.0/gdk-pixbuf.loaders"
fi

WGDKPBL="$(echo $GDKPBL | sed 's,/,\\,g')"

if test "x$AUTOWINE" = "xyes" ; then
  log_write 1 "Creating configuration files"
  if ! mkdir -p $DLLSPREFIX/etc/pango ||
     ! $DLLSPREFIX/bin/pango-querymodules.exe > $DLLSPREFIX/etc/pango/pango.modules ||
     ! $DLLSPREFIX/bin/gdk-pixbuf-query-loaders.exe > $DLLSPREFIX/$GDKPBL
  then
    log_error "Failed to create configuration files in wine."
    exit 1
  fi
fi

log_write 1 "Creating crosser.txt"
(
  echo "Dllstack"
  echo "========"
  echo "Version=\"$CROSSER_VERSION\""
  echo "Setup=\"$SETUP\""
  echo "Set=\"$VERSIONSET\""
  echo "Built=\"$(date +"%d.%m.%Y")\""
  echo "CROSSER_QT=\"$CROSSER_QT\""
) > "$DLLSPREFIX/crosser.txt"

log_write 1 "Creating configuration files"
mkdir -p "$DLLSPREFIX/etc/gtk-3.0"
(
  echo -n -e "[Settings]\r\n"
  echo -n -e "gtk-fallback-icon-theme = gnome\r\n"
  echo -n -e "gtk-button-images = true\r\n"
  echo -n -e "gtk-menu-images = true\r\n"
) > "$DLLSPREFIX/etc/gtk-3.0/settings.ini"

mkdir -p "$DLLSPREFIX/etc/gtk-2.0"
(
  echo -n -e "gtk-icon-theme-name = gnome\r\n"
) > "$DLLSPREFIX/etc/gtk-2.0/gtkrc"

log_write 1 "Creating setup.bat"
(
  echo -n -e "if not exist etc\pango mkdir etc\pango\r\n"
  echo -n -e "bin\pango-querymodules.exe > etc\pango\pango.modules\r\n"
  echo -n -e "bin\gdk-pixbuf-query-loaders.exe > $WGDKPBL\r\n"
  echo -n -e "bin\gtk-update-icon-cache.exe share\icons\Adwaita\r\n"
  echo -n -e "bin\gtk-update-icon-cache.exe share\icons\gnome\r\n"
  echo -n -e "bin\gtk-update-icon-cache.exe share\icons\hicolor\r\n"
) > "$DLLSPREFIX/setup.bat"

log_write 1 "Creating launch.bat"
(
  echo -n -e "set PATH=%~dp0\\\bin;%PATH%\r\n"
) > "$DLLSPREFIX/launch.bat"

if test "x$CROSSER_QT" = "xyes"
then
    echo -n -e "set QT_PLUGIN_PATH=%~dp0\\\plugins\r\n" >> "$DLLSPREFIX/launch.bat"
fi

log_write 1 "IMPORTANT: Remember to run setup.bat when installing to target"

log_write 1 "SUCCESS"
