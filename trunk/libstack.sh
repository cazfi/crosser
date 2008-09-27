#!/bin/bash

# libstack.sh: Cross-compile set of libraries for Windows target.
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

MAINDIR=$(cd $(dirname $0) ; pwd)

export CROSSER_OPTION_JPEG=on

if test "x$1" = "x-h" || test "x$1" = "x--help"
then
  echo "Usage: $(basename $0) [[-h|--help]|[-v|--version]|[install prefix]] [versionset]"
  exit 0
fi

if test "x$1" = "x-v" || test "x$1" = "x--version"
then
  echo "Windows library stack builder for Crosser $CROSSER_VERSION"
  exit 0
fi

# In order to give local setup opportunity to override versions,
# we have to load versionset before build_setup.conf
# helpers.sh requires environment to be set up by build_setup.conf.
if test "x$2" != "x" ; then
  VERSIONSET="$2"
else
  VERSIONSET="current"
fi
if test -e $MAINDIR/setups/$VERSIONSET.versions
then
  . $MAINDIR/setups/$VERSIONSET.versions
else
  # Versions being unset do not prevent loading of build_setup.conf and helper.sh,
  # resulting environment would just be unusable for building.
  # We are not going to build anything, but just issuing error message - and for
  # that we read log_error from helpers.sh
  ERR_MSG="Cannot find versionset \"$VERSIONSET.versions\""
fi

. $MAINDIR/build_setup.conf
. $MAINDIR/scripts/helpers.sh
. $MAINDIR/scripts/packethandlers.sh

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
  PREFIX="$1"
fi

# $1 - Component
# $2 - Version
# $3 - Extra configure options
build_component_srcdir()
{
  build_component_full "$1" "$2" "$3" "src"
}

# $1 - Component
# $2 - Version
# $3 - Extra configure options
build_component()
{
  build_component_full "$1" "$2" "$3"
}

# $1 - Component
# $2 - Version
# $3 - Extra configure options
# $4 - Build in src dir?
# $5 - Overwrite libtool
build_component_full()
{
  log_packet "$1"

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  if test "x$4" != "xsrc" ; then
    BUILDDIR="$MAINBUILDDIR/$1"
    if ! mkdir -p "$BUILDDIR"
    then
      log_error "Failed to create directory $BUILDDIR"
      return 1
    fi
    cd $BUILDDIR
    SRCDIR="$MAINSRCDIR/$SUBDIR"
  else
    if ! cd $MAINSRCDIR/$SUBDIR
    then
      log_error "Cannot change to directory $MAINSRCDIR/$SUBDIR"
      return 1
    fi
    SRCDIR="."
  fi

  CONFOPTIONS="--prefix=$PREFIX --build=$BUILD --host=$TARGET --target=$TARGET $3"

  export CPPFLAGS="-isystem $PREFIX/include -isystem $TGT_HEADERS $TGT_MARCH $USER_CPPFLAGS"
  export LDFLAGS="-L$PREFIX/lib $USER_LDFLAGS"

  log_write 1 "Configuring: $1"
  log_write 3 "  Options: \"$CONFOPTIONS\""
  log_flags

  if ! $SRCDIR/configure $CONFOPTIONS >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
  then
    log_error "Configure for $1 failed"
    return 1
  fi

  if test "x$5" = "xoverwrite" ; then
    log_write 2 "Copying working libtool to $1"
    if ! cp $MAINBUILDDIR/libtool/libtool .
    then
      log_error "Failed to copy libtool"
      return 1
    fi
  elif test "x$5" != "x" ; then
    log_error "Illegal libtool overwrite parameter $5"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default] install"

  if ! make  >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make install >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
  then
    log_error "Install for $1 failed"
    return 1
  fi
}

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

  if ! cd $MAINSRCDIR/$SUBDIR
  then
    log_error "Cannot change to directory $MAINSRCDIR/$SUBDIR"
    return 1
  fi

  export CPPFLAGS="-isystem $PREFIX/include -isystem $TGT_HEADERS $USER_CPPFLAGS"
  export LDFLAGS="-L$PREFIX/lib $USER_LDFLAGS"

  CONFOPTIONS="--prefix=$PREFIX --shared $3"

  # TODO: zlib build doesn't like this variable, check why.
  unset TARGET_ARCH

  log_write 1 "Configuring: $1"
  log_write 3 "  Options: \"$CONFOPTIONS\""
  log_flags

  if ! ./configure $CONFOPTIONS >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
  then
    log_error "Configure for $1 failed"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default] install"

  if ! make >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make install  >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
  then
    log_error "Install for $1 failed"
    return 1
  fi

  if ! cp $PREFIX/lib/libz.dll* $PREFIX/bin/ ||
     ! mv $PREFIX/lib/libz.a    $PREFIX/bin/
  then
    log_error "Failed to move libz dll:s to correct directory"
    return 1
  fi
}

# Update one autotools auxiliary file for component
#
# $1 - Source directory in source hierarchy
# $2 - Aux file
update_aux_file()
{
  # Update only those files that already exist in target directory
  if test -e $MAINSRCDIR/$1/$2 ; then
    log_write 2 "Updating $2"
    if ! cp $MAINDIR/scripts/aux/$2 $MAINSRCDIR/$1/
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

  if ! update_aux_file $SUBDIR config.guess ||
     ! update_aux_file $SUBDIR config.sub   ||
     ! update_aux_file $SUBDIR install-sh   ||
     ! update_aux_file $SUBDIR ltmain.sh
  then
    log_error "Failed to update auxiliary files in directory $SUBDIR"
    return 1
  fi
}

cd $(dirname $0)

if ! source $MAINSETUPDIR/native.sh ; then
  log_error "Failed to read $MAINSETUPDIR/native.sh"
  exit 1
fi
NATIVE_ARCH="$TMP_ARCH"
NATIVE_OS="$TMP_OS"
BUILD="$NATIVE_ARCH-$NATIVE_OS"

SETUP="win32"

if ! test -e "$MAINSETUPDIR/$SETUP.conf" ; then
  log_error "Can't find setup \"$SETUP.conf\""
  exit 1
fi
source "$MAINSETUPDIR/$SETUP.conf"

if test "x$LIBSTACK" = "xno"
then
  log_error "Libstack.sh cannot be used with configuration \"$SETUP\"."
  exit 1
fi

if test "x$TARGET_VENDOR" = "x"
then
  TARGET="$TARGET_ARCH-$TARGET_OS"
else
  TARGET="$TARGET_ARCH-$TARGET_VENDOR-$TARGET_OS"
fi

if test -d /usr/$TARGET/include
then
  export TGT_HEADERS=/usr/$TARGET/include
fi

TGT_MARCH="-march=$TARGET_ARCH"

export LIBC_MODE="none"

export PREFIX=$(setup_prefix_default "$(pwd)/install-<TARGET>-<DATE>" "$PREFIX")

export USER_CPPFLGS="$CPPFLAGS"
export USER_LDFLAGS="$LDFLAGS"
export USER_CFLAGS="$CFLAGS"
export USER_CXXFLAGS="$CXXFLAGS"

log_write 2 "Install:    \"$PREFIX\""
log_write 2 "Src:        \"$MAINSRCDIR\""
log_write 2 "Log:        \"$MAINLOGDIR\""
log_write 2 "Build:      \"$MAINBUILDDIR\""
log_write 2 "Versionset: \"$VERSIONSET\""

if ! remove_dir "$MAINSRCDIR"   ||
   ! remove_dir "$MAINBUILDDIR" ||
   ! remove_dir "$PREFIX"
then
  log_error "Failed to remove old directories"
  exit 1
fi

if ! mkdir -p $MAINSRCDIR
then
  log_error "Cannot create directory $MAINSRCDIR"
  exit 1
fi

if ! mkdir -p $MAINBUILDDIR
then
  log_error "Cannot create directory $MAINBUILDDIR"
  exit 1
fi

if ! mkdir -p $PREFIX/man/man1
then
  log_error "Cannot create target directory hierarchy under $PREFIX"
  exit 1
fi

if test "x$CROSSER_DOWNLOAD" = "xyes"
then
  if ! $MAINDIR/download_packets.sh "win,sdl"
  then
    log_error "Downloading packets failed"
    exit 1
  fi
fi

export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig

BASEVER_LIBTOOL="$(basever_libtool $VERSION_LIBTOOL)"

if ! unpack_component  libtool    $VERSION_LIBTOOL          ||
   ! build_component   libtool    $BASEVER_LIBTOOL          ||
   ! unpack_component  libiconv   $VERSION_ICONV            ||
   ! build_component   libiconv   $VERSION_ICONV            ||
   ! unpack_component  zlib       $VERSION_ZLIB             ||
   ! patch_src zlib               zlib_cctest               ||
   ! patch_src zlib               zlib_seeko                ||
   ! patch_src zlib               zlib_nolibc               ||
   ! patch_src zlib               zlib_dllext               ||
   ! build_zlib        zlib                                 ||
   ! unpack_component  libpng     $VERSION_PNG              ||
   ! build_component   libpng     $VERSION_PNG              ||
   ! unpack_component  readline   $VERSION_READLINE         \
                       "" ""      $PATCHES_READLINE         ||
   ! patch_readline                                         ||
   ! build_component   readline   $VERSION_READLINE         ||
   ! unpack_component  gettext    $VERSION_GETTEXT          ||
   ! (export LIBS="-liconv" && build_component gettext  $VERSION_GETTEXT) ||
   ! unpack_component  glib       $VERSION_GLIB             ||
   ! patch_src glib-$VERSION_GLIB glib_acsizeof             ||
   ! patch_src glib-$VERSION_GLIB glib_stackgrow            ||
   ! ( ! cmp_versions $VERSION_GLIB 2.18.0    ||
       patch_src glib-$VERSION_GLIB glib_gmoddef    )       ||
   ! autogen_component glib       $VERSION_GLIB  "automake autoconf" ||
   ! build_component   glib       $VERSION_GLIB
then
  log_error "Build failed"
  exit 1
fi

if test "x$CROSSER_OPTION_JPEG" = "xon"
then
  if ! unpack_component libjpeg6b  $VERSION_JPEG            ||
     ! patch_src        libjpeg6b  jpeg_ltcompile           ||
     ! patch_src        libjpeg6b  jpeg_ar                  ||
     ! patch_src        libjpeg6b  jpeg_noundef             ||
     ! update_aux_files     libjpeg6b  $VERSION_JPEG        ||
     ! build_component_full libjpeg6b  $VERSION_JPEG "--enable-shared" "" "overwrite"
  then
    log_error "Libjpeg build failed"
    exit 1
  fi
else
  CONF_JPEG_TIFF="--disable-jpeg"
  CONF_JPEG_GTK="--without-libjpeg"
fi

if is_minimum_version $VERSION_GTK 2.13.0
then
  CONF_JPEG_GTK="$CONF_JPEG_GTK --without-libjasper"
fi

if ! unpack_component tiff       $VERSION_TIFF
then
  log_error "Tiff unpacking failed"
  exit 1
fi

if ! patch_src tiff-$VERSION_TIFF tiff_config_headers       ||
   ! ( ! cmp_versions $VERSION_TIFF 4.0.0alpha ||
       patch_src tiff-$VERSION_TIFF tiff4alpha_largefile )
then
  log_error "Tiff patching failed"
  exit 1
fi

if is_smaller_version $VERSION_TIFF 4.0.0beta1
then
  log_write 1 "Removing upstream libtiff config"
  if ! rm $MAINSRCDIR/tiff-$VERSION_TIFF/libtiff/tiffconf.h
  then
    log_error "Failed to remove old tiffconf.h"
    exit 1
  fi
fi

if ! autogen_component tiff       $VERSION_TIFF                   ||
   ! build_component   tiff       $VERSION_TIFF "$CONF_JPEG_TIFF" ||
   ! unpack_component  expat      $VERSION_EXPAT                  ||
   ! build_component   expat      $VERSION_EXPAT
then
  log_error "Build failed"
  exit 1
fi

if ! unpack_component  freetype   $VERSION_FREETYPE               ||
   ! ( is_minimum_version $VERSION_FREETYPE 2.3.6 ||
       patch_src freetype-$VERSION_FREETYPE freetype_dll )        ||
   ! ( is_minimum_version $VERSION_FREETYPE 2.3.6                 ||
       autogen_component freetype   $VERSION_FREETYPE )           ||
   ! build_component   freetype   $VERSION_FREETYPE
then
  log_error "Freetype build failed"
  exit 1
fi

if ! unpack_component  fontconfig $VERSION_FONTCONFIG             ||
   ! patch_src fontconfig-$VERSION_FONTCONFIG fontconfig_buildsys_flags ||
   ! autogen_component fontconfig $VERSION_FONTCONFIG             ||
   ! build_component   fontconfig $VERSION_FONTCONFIG             \
     "--with-freetype-config=$PREFIX/bin/freetype-config --with-arch=$TARGET" ||
   ! unpack_component  pixman     $VERSION_PIXMAN                 ||
   ! build_component   pixman     $VERSION_PIXMAN                 \
     "--disable-gtk"                                              ||
   ! unpack_component  cairo      $VERSION_CAIRO                  ||
   ! build_component   cairo      $VERSION_CAIRO "--disable-xlib" ||
   ! unpack_component  pango      $VERSION_PANGO                  ||
   ! build_component   pango      $VERSION_PANGO                  ||
   ! unpack_component  atk        $VERSION_ATK                    ||
   ! ( is_smaller_version $VERSION_ATK     1.24.0  ||
       patch_src          atk-$VERSION_ATK atk_def    )           ||
   ! build_component   atk        $VERSION_ATK
then
  log_error "Build failed"
  exit 1
fi

if ! unpack_component  gtk+       $VERSION_GTK                    ||
   ! ( is_minimum_version $VERSION_GTK      2.12.10 ||
       patch_src gtk+-$VERSION_GTK          gtk_blddir )          ||
   ! ( is_minimum_version $VERSION_GTK      2.13.2 ||
       patch_src gtk+-$VERSION_GTK          gtk_check_cxx )       ||
   ! autogen_component gtk+       $VERSION_GTK                    ||
   ! build_component   gtk+       $VERSION_GTK \
     "--disable-cups --disable-explicit-deps $CONF_JPEG_GTK"      ||
   ! unpack_component gtk-engines $VERSION_GTK_ENG                ||
   ! build_component  gtk-engines $VERSION_GTK_ENG
then
  log_error "gtk+ stack build failed"
  exit 1
fi

if test "x$AUTOWINE" = "xyes" ; then
  log_write 1 "Creating configuration files"
  if ! mkdir -p $PREFIX/etc/pango ||
     ! $PREFIX/bin/pango-querymodules.exe > $PREFIX/etc/pango/pango.modules ||
     ! $PREFIX/bin/gdk-pixbuf-query-loaders.exe > $PREFIX/etc/gtk-2.0/gdk-pixbuf.loaders
  then
    log_error "Failed to create configuration files in wine."
    exit 1
  fi
fi
log_write 1 "IMPORTANT: Remember to create configuration files when installing to target"

if ! unpack_component  SDL        $VERSION_SDL          ||
   ! build_component   SDL        $VERSION_SDL          ||
   ! unpack_component  SDL_image  $VERSION_SDL_IMAGE    ||
   ! build_component   SDL_image  $VERSION_SDL_IMAGE
then
  log_error "SDL stack build failed"
  exit 1
fi

generate_setup_scripts "$PREFIX"

log_write 1 "SUCCESS"
