#!/bin/bash

# dllstack.sh: Cross-compile set of libraries for Windows target.
#
# (c) 2008-2012 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

CROSSER_MAINDIR="$(cd "$(dirname "$0")" ; pwd)"

if ! test -e "$CROSSER_MAINDIR/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

export CROSSER_OPTION_JPEG=on

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
# $2 - Version
# $3 - Extra configure options
build_component()
{
  build_component_full "$1" "$1" "$2" "$3"
}

# $1 - Component
# $2 - Version
# $3 - Extra configure options
build_component_host()
{
  if ! build_component_full "host-$1" "$1" "$2" "$3" "native"
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

# $1 - Build dir
# $2 - Component
# $3 - Version, "0" to indicate that there isn't package to build after all
# $4 - Extra configure options
# $5 - Build type ('native' | 'windres')
build_component_full()
{
  log_packet "$1"

  if test "x$3" = "x0"
  then
    return 0
  fi

  SUBDIR="$(src_subdir $2 $3)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $2 version $3"
    return 1
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

  if test "x$5" = "xnative"
  then
    CONFOPTIONS="--prefix=$NATIVE_PREFIX $4"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "x$5" = "xwindres"
  then
    CONFOPTIONS="--prefix=$DLLSPREFIX --build=$BUILD --host=$TARGET --target=$TARGET $4"
    unset CPPFLAGS
    export LDFLAGS="-L$DLLSPREFIX/lib $USER_LDFLAGS"
  else
    CONFOPTIONS="--prefix=$DLLSPREFIX --build=$BUILD --host=$TARGET --target=$TARGET $4"
    export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS $USER_CPPFLAGS"
    export LDFLAGS="-L$DLLSPREFIX/lib $USER_LDFLAGS"
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

  if ! make  >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
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

  export CC=$TARGET-gcc
  export RANLIB=$TARGET-ranlib
  export AR=$TARGET-ar

  (
  if ! cd "$CROSSER_SRCDIR/$SUBDIR"
  then
    log_error "Cannot change to directory $CROSSER_SRCDIR/$SUBDIR"
    return 1
  fi

  export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS $USER_CPPFLAGS"
  export LDFLAGS="-L$DLLSPREFIX/lib $USER_LDFLAGS"

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

  if ! make >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
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
  export CPPFLAGS="-isystem $DLLSPREFIX/include -isystem $TGT_HEADERS $USER_CPPFLAGS"
  export LDFLAGS="-L$DLLSPREFIX/lib $USER_LDFLAGS"

  log_write 1 "Building $1"
  log_write 3 "  Make targets: libbz2.a bzip2 bzip2recover & install"
  log_flags

  if ! make libbz2.a bzip2 bzip2recover \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Install for $1 failed"
    return 1
  fi
  )
}

# Update one autotools auxiliary file for component
#
# $1 - Source directory in source hierarchy
# $2 - Aux file
update_aux_file()
{
  # Update only those files that already exist in target directory
  if test -e "$CROSSER_SRCDIR/$1/$2" ; then
    log_write 2 "Updating $2"
    if ! cp "$CROSSER_MAINDIR/scripts/aux/$2" "$CROSSER_SRCDIR/$1/"
    then
      return 1
    fi
  fi
}

# Update autotools auxiliary files for component
#
# $1 - Component
# $2 - Version
update_aux_files() {

  log_write 1 "Updating auxiliary files for $1"

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  if ! update_aux_file "$SUBDIR" config.guess ||
     ! update_aux_file "$SUBDIR" config.sub   ||
     ! update_aux_file "$SUBDIR" install-sh   ||
     ! update_aux_file "$SUBDIR" ltmain.sh
  then
    log_error "Failed to update auxiliary files in directory $SUBDIR"
    return 1
  fi
}

cd $(dirname $0)

if ! . "$CROSSER_MAINDIR/setups/native.sh" ; then
  log_error "Failed to read $CROSSER_MAINDIR/setups/native.sh"
  exit 1
fi
NATIVE_ARCH="$TMP_ARCH"
NATIVE_OS="$TMP_OS"
BUILD="$NATIVE_ARCH-$NATIVE_OS"

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

export DLLSPREFIX=$(setup_prefix_default "$HOME/.crosser/<VERSION>/<VERSIONSET>/winstack" "$DLLSPREFIX")
export NATIVE_PREFIX=$(setup_prefix_default "$HOME/.crosser/<VERSION>/<VERSIONSET>/dllshost" \
                       "$DLLSHOST_PREFIX")

export USER_CPPFLGS="$CPPFLAGS"
export USER_LDFLAGS="$LDFLAGS"
export USER_CFLAGS="$CFLAGS"
export USER_CXXFLAGS="$CXXFLAGS"

log_write 2 "Install:    \"$DLLSPREFIX\""
log_write 2 "Src:        \"$CROSSER_SRCDIR\""
log_write 2 "Log:        \"$CROSSER_LOGDIR\""
log_write 2 "Build:      \"$CROSSER_BUILDDIR\""
log_write 2 "Versionset: \"$VERSIONSET\""

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
  if ! (cd "$PACKETDIR" && "$CROSSER_MAINDIR/scripts/download_packets.sh" "win" )
  then
    log_error "Downloading packets failed"
    exit 1
  fi
fi

export PKG_CONFIG_LIBDIR="$NATIVE_PREFIX/lib/pkgconfig"

BASEVER_LIBTOOL="$(basever_libtool $VERSION_LIBTOOL)"
GLIB_VARS="$(read_configure_vars glib)"
GETTEXT_VARS="$(read_configure_vars gettext)"
IM_VARS="$(read_configure_vars imagemagick)"

# glib_acsizeof -patch is required only when running autogen for glib
if ! unpack_component     autoconf   $VERSION_AUTOCONF      ||
   ! build_component_host autoconf   $VERSION_AUTOCONF      ||
   ! free_component       autoconf   $VERSION_AUTOCONF "host-autoconf" ||
   ! unpack_component     automake   $VERSION_AUTOMAKE      ||
   ! build_component_host automake   $VERSION_AUTOMAKE      ||
   ! free_component       automake   $VERSION_AUTOMAKE "host-automake" ||
   ! unpack_component     libtool    $VERSION_LIBTOOL       ||
   ! patch_src libtool-$VERSION_LIBTOOL libtool_bash        ||
   ! build_component_host libtool    $BASEVER_LIBTOOL       ||
   ! free_build           "host-libtool"                    ||
   ! unpack_component     libffi     $VERSION_FFI           ||
   ! build_component_host libffi     $VERSION_FFI           ||
   ! free_build           "host-libffi"                     ||
   ! unpack_component     glib       $VERSION_GLIB          ||
   ! (is_smaller_version $VERSION_GLIB 2.32.0 ||
      is_minimum_version $VERSION_GLIB 2.34.0 ||
      (patch_src glib-$VERSION_GLIB glib_unknown_mime     &&   
       patch_src glib-$VERSION_GLIB glib_uncond_check_hdr &&
       autogen_component glib       $VERSION_GLIB \
          "autoconf" ))                                     ||
   ! build_component_host glib $VERSION_GLIB                ||
   ! free_build           "host-glib"                       ||
   ! unpack_component     pkg-config $VERSION_PKG_CONFIG    ||
   ! (! cmp_versions $VERSION_PKG_CONFIG 0.25 ||
      patch_src pkg-config-$VERSION_PKG_CONFIG pkgconfig_ac266) ||
   ! build_component_host pkg-config $VERSION_PKG_CONFIG    ||
   ! free_component       pkg-config $VERSION_PKG_CONFIG "host-pkg-config"
then
  log_error "Native build failed"
  exit 1
fi

export PKG_CONFIG_LIBDIR="$DLLSPREFIX/lib/pkgconfig"

if cmp_versions $VERSION_SQLITE 3.7.14
then
  SQL_VERSTR="3071400"
elif cmp_versions $VERSION_SQLITE 3.7.13
then
  SQL_VERSTR="3071300"
fi

if ! build_component   libtool    $BASEVER_LIBTOOL                   ||
   ! free_component    libtool    $BASEVER_LIBTOOL "libtool"         ||
   ! unpack_component  libiconv   $VERSION_ICONV                     ||
   ! build_component   libiconv   $VERSION_ICONV                     ||
   ! free_component    libiconv   $VERSION_ICONV "libiconv"          ||
   ! unpack_component  zlib       $VERSION_ZLIB                      ||
   ! patch_src zlib               zlib_seeko-1.2.6-2                 ||
   ! patch_src zlib               zlib_nolibc-1.2.6-2                ||
   ! patch_src zlib               zlib_dllext                        ||
   ! build_zlib        zlib       $VERSION_ZLIB                      ||
   ! free_src          zlib       $VERSION_ZLIB                      ||
   ! unpack_component  bzip2      $VERSION_BZIP2                     ||
   ! patch_src bzip2-$VERSION_BZIP2 bzip2_unhardcodecc               ||
   ! patch_src bzip2-$VERSION_BZIP2 bzip2_incpathsep                 ||
   ! patch_src bzip2-$VERSION_BZIP2 bzip2_winapi                     ||
   ! build_bzip2       bzip2      $VERSION_BZIP2                     ||
   ! free_src          bzip2      $VERSION_BZIP2                     ||
   ! unpack_component  xz         $VERSION_XZ                        ||
   ! build_component_full xz xz   $VERSION_XZ "" "windres"           ||
   ! free_component    xz         $VERSION_XZ "xz"                   ||
   ! unpack_component  curl       $VERSION_CURL                      ||
   ! build_component   curl       $VERSION_CURL                      ||
   ! free_component    curl       $VERSION_CURL "curl"               ||
   ! unpack_component  sqlite     $VERSION_SQLITE                    \
     "" "sqlite-autoconf-${SQL_VERSTR}"                              ||
   ! build_component_full sqlite sqlite-autoconf $SQL_VERSTR         ||
   ! free_component    sqlite-autoconf $SQL_VERSTR "sqlite"          ||
   ! unpack_component  ImageMagick $VERSION_IMAGEMAGICK              ||
   ! build_component   ImageMagick $VERSION_IMAGEMAGICK              \
     "--without-bzlib"                                               ||
   ! free_component    ImageMagick $VERSION_IMAGEMAGICK "ImageMagick" ||
   ! unpack_component  libpng     $VERSION_PNG                       ||
   ! build_component   libpng     $VERSION_PNG                       ||
   ! free_component    libpng     $VERSION_PNG "libpng"              ||
   ! unpack_component  gettext    $VERSION_GETTEXT                   ||
   ! ( patch_src gettext-$VERSION_GETTEXT gettext_cxx_tools &&
       ( cd "$CROSSER_SRCDIR/gettext-$VERSION_GETTEXT" &&
         libtoolize &&
         ./autogen.sh --quick --skip-gnulib ) \
         >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
     )                                                               ||
   ! (export LIBS="-liconv" && build_component gettext  $VERSION_GETTEXT \
                               "$GETTEXT_VARS --enable-relocatable" ) ||
   ! free_component    gettext    $VERSION_GETTEXT "gettext"          ||
   ! build_component   libffi     $VERSION_FFI                        ||
   ! free_component    libffi     $VERSION_FFI    "libffi"            ||
   ! build_component   glib       $VERSION_GLIB             \
       "$GLIB_VARS"                                                   ||
   ! free_component    glib       $VERSION_GLIB "glib"
then
  log_error "Build failed"
  exit 1
fi

if test "x$CROSSER_OPTION_JPEG" = "xon"
then
  if ! unpack_component jpeg $VERSION_JPEG "" "jpegsrc.v${VERSION_JPEG}" ||
     ! build_component jpeg $VERSION_JPEG "--enable-shared"              ||
     ! free_component jpeg $VERSION_JPEG "jpeg"
  then
    log_error "Libjpeg build failed"
    exit 1
  fi
else
  CONF_JPEG_TIFF="--disable-jpeg"
  CONF_JPEG_GTK="--without-libjpeg"
fi

if is_minimum_version $VERSION_GTK2 2.13.0
then
  CONF_JPEG_GTK="$CONF_JPEG_GTK --without-libjasper"
fi

if ! unpack_component tiff       $VERSION_TIFF
then
  log_error "Tiff unpacking failed"
  exit 1
fi

if ! ( is_minimum_version $VERSION_TIFF 3.9.5 ||
       patch_src tiff-$VERSION_TIFF tiff_config_headers ) ||
   ! ( is_smaller_version $VERSION_TIFF 3.9.5 ||
       patch_src tiff-$VERSION_TIFF tiff_config_headers_395 )
then
  log_error "Tiff patching failed"
  exit 1
fi

if is_smaller_version $VERSION_TIFF 3.9.0
then
  log_write 1 "Removing upstream libtiff config"
  if ! rm "$CROSSER_SRCDIR/tiff-$VERSION_TIFF/libtiff/tiffconf.h"
  then
    log_error "Failed to remove old tiffconf.h"
    exit 1
  fi
fi

if ! ( is_minimum_version $VERSION_TIFF 3.9.0 ||
      autogen_component tiff       $VERSION_TIFF )                ||
   ! build_component_full                                         \
     tiff tiff $VERSION_TIFF "$CONF_JPEG_TIFF"                    ||
   ! free_component    tiff       $VERSION_TIFF "tiff"            ||
   ! unpack_component  expat      $VERSION_EXPAT                  ||
   ! build_component   expat      $VERSION_EXPAT                  ||
   ! free_component    expat      $VERSION_EXPAT "expat"
then
  log_error "Build failed"
  exit 1
fi

if ! unpack_component  freetype   $VERSION_FREETYPE               ||
   ! build_component   freetype   $VERSION_FREETYPE               \
     "--without-bzip2"                                            ||
   ! free_component    freetype   $VERSION_FREETYPE "freetype"
then
  log_error "Freetype build failed"
  exit 1
fi

if ! unpack_component  fontconfig $VERSION_FONTCONFIG               ||
   ! ( is_minimum_version $VERSION_FONTCONFIG 2.10 ||
       (patch_src fontconfig-$VERSION_FONTCONFIG fontconfig_buildsys_flags &&
        autogen_component fontconfig $VERSION_FONTCONFIG \
        "libtoolize aclocal automake autoconf" ))                   ||
   ! build_component   fontconfig $VERSION_FONTCONFIG                   \
     "--with-freetype-config=$DLLSPREFIX/bin/freetype-config --with-arch=$TARGET" ||
   ! free_component    fontconfig $VERSION_FONTCONFIG "fontconfig" ||
   ! unpack_component  pixman     $VERSION_PIXMAN                 ||
   ! build_component   pixman     $VERSION_PIXMAN                 \
     "--disable-gtk"                                              ||
   ! free_component    pixman     $VERSION_PIXMAN "pixman"        ||
   ! unpack_component  cairo      $VERSION_CAIRO                  ||
   ! rm -f "$CROSSER_SRCDIR/cairo-$VERSION_CAIRO/src/cairo-features.h" ||
   ! patch_src         cairo-$VERSION_CAIRO cairo_epsilon         ||
   ! ( is_smaller_version $VERSION_CAIRO 1.10.0 ||
       patch_src         cairo-$VERSION_CAIRO cairo_ffs )         ||
   ! build_component   cairo      $VERSION_CAIRO                  \
     "--disable-xlib --enable-win32"                              ||
   ! free_component    cairo      $VERSION_CAIRO "cairo"          ||
   ! unpack_component  pango      $VERSION_PANGO                  ||
   ! CXX="$TARGET-g++" build_component   pango      $VERSION_PANGO                  ||
   ! free_component    pango      $VERSION_PANGO "pango"          ||
   ! unpack_component  atk        $VERSION_ATK                    ||
   ! ( is_smaller_version $VERSION_ATK     1.24.0  ||
       is_minimum_version $VERSION_ATK     2.2.0   ||
       patch_src          atk-$VERSION_ATK atk_def    )           ||
   ! autogen_component atk        $VERSION_ATK                    \
     "libtoolize aclocal automake autoconf"                       ||
   ! build_component   atk        $VERSION_ATK                    ||
   ! free_component    atk        $VERSION_ATK "atk"
then
  log_error "Build failed"
  exit 1
fi

if ! ( is_smaller_version $VERSION_GTK2 2.22.0 ||
       ( unpack_component gdk-pixbuf $VERSION_GDK_PIXBUF &&
         ( is_smaller_version $VERSION_GTK2 2.24.0 ||
           is_greater_version $VERSION_GDK_PIXBUF 2.24.0 ||
           patch_src gdk-pixbuf-$VERSION_GDK_PIXBUF gdkpixbuf_gdiplusdef ) &&
         ( ! cmp_versions $VERSION_GDK_PIXBUF 2.24.1 ||
           patch_src gdk-pixbuf-$VERSION_GDK_PIXBUF gdkpixbuf_animiterinit) &&
         autogen_component gdk-pixbuf $VERSION_GDK_PIXBUF &&
         build_component gdk-pixbuf $VERSION_GDK_PIXBUF &&
         free_component  gdk-pixbuf $VERSION_GDK_PIXBUF "gdk-pixbuf")) ||
   ! unpack_component  gtk2       $VERSION_GTK2                   ||
   ! ( is_minimum_version $VERSION_GTK2     2.12.10 ||
       patch_src gtk+-$VERSION_GTK2         gtk_blddir )          ||
   ! ( is_minimum_version $VERSION_GTK2     2.13.2 ||
       patch_src gtk+-$VERSION_GTK2         gtk_check_cxx )       ||
   ! ( is_smaller_version $VERSION_GTK2     2.14.0 ||
       is_minimum_version $VERSION_GTK2     2.16.0 ||
       patch_src gtk+-$VERSION_GTK2         gtk_gailutildef )     ||
   ! ( is_minimum_version $VERSION_GTK2     2.16.0 ||
       autogen_component gtk+       $VERSION_GTK2   \
         "libtoolize aclocal automake autoconf" )                 ||
   ! build_component_full gtk2 gtk+ $VERSION_GTK2                 \
     "--disable-cups --disable-explicit-deps $CONF_JPEG_GTK"      ||
   ! free_component   gtk+        $VERSION_GTK2 "gtk2"            ||
   ! unpack_component gtk3        $VERSION_GTK3                   ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gdk/gdkconfig.h     ||
   ! ( is_minimum_version $VERSION_GTK3 3.2.0 ||
       patch_src gtk+-$VERSION_GTK3 gtk3_marshalers )             ||
   ! ( is_smaller_version $VERSION_GTK3 3.4.0 ||
       is_minimum_version $VERSION_GTK3 3.6.0 ||
       patch_src gtk+-$VERSION_GTK3 gtk3_isinf )                  ||
   ! build_component_full gtk3 gtk+ $VERSION_GTK3                 ||
   ! free_component   gtk+        $VERSION_GTK3 "gtk3"            ||
   ! unpack_component gtk-engines $VERSION_GTK_ENG                ||
   ! build_component  gtk-engines $VERSION_GTK_ENG                ||
   ! free_component   gtk-engines $VERSION_GTK_ENG "gtk-engines"
then
  log_error "gtk+ stack build failed"
  exit 1
fi

if ! unpack_component  SDL        $VERSION_SDL          ||
   ! build_component   SDL        $VERSION_SDL          ||
   ! free_component    SDL        $VERSION_SDL "SDL"    ||
   ! rm "$DLLSPREFIX/lib/libSDLmain.la"                 ||
   ! unpack_component  SDL_image  $VERSION_SDL_IMAGE    ||
   ! build_component   SDL_image  $VERSION_SDL_IMAGE    ||
   ! free_component    SDL_image  $VERSION_SDL_IMAGE "SDL_image"
then
  log_error "SDL stack build failed"
  exit 1
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
log_write 1 "Creating setup.bat"
(
  echo -n -e "if not exist etc\pango mkdir etc\pango\r\n"
  echo -n -e "bin\pango-querymodules.exe > etc\pango\pango.modules\r\n"
  echo -n -e "bin\gdk-pixbuf-query-loaders.exe > $WGDKPBL\r\n"
) > "$DLLSPREFIX/setup.bat"
log_write 1 "IMPORTANT: Remember to run setup.bat when installing to target"

log_write 1 "SUCCESS"
