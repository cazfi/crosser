#!/bin/bash

# download_packets.sh: Source package downloader
#
# (c) 2008-2014 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.


# $1 - Base URL
# $2 - Filename
# $3 - Download directory
download_file() {
  if test "x$2" = "x" ; then
    return 0
  fi

  if test "x$3" != "x"
  then
    DLDIR="$3"
  else
    DLDIR="."
  fi

  TIMEPART=$(date +%y%m%d%H%M)

  if test -f filelist.txt
  then
    if grep ": $2\$" filelist.txt > /dev/null
    then
      sed "s/: .* : $2\$/: $TIMEPART : $2/" filelist.txt > filelist.tmp
      mv filelist.tmp filelist.txt
      APPEND=no
    else
      APPEND=yes
    fi
  else
    # Creating new filelist
    if test "x$CROSSER_GROUP" != "x" ; then
      touch filelist.txt
      if ! chown ":$CROSSER_GROUP" filelist.txt ; then
        echo "Cannot set owner group for filelist.txt" >&2
        return 1
      fi
    fi
    APPEND=yes
  fi

  if test "x$APPEND" = "xyes"
  then
    echo "$TIMEPART : $TIMEPART : $2" >> filelist.txt
  fi

  if test -f "$DLDIR/$2"
  then
    echo "Already has $2, skipping"
    return 0
  fi

  if ! ( cd "$DLDIR" && wget -T 180 -t 2 "$1$2" ) ; then
    echo "Download of $2 failed" >&2
    return 1
  fi

  if test "x$CROSSER_GROUP" != "x" ; then
    if ! chown ":$CROSSER_GROUP" "$2" ; then
      echo "Cannot set owner group for \"$2\"" >&2
      return 1
    fi
  fi

  echo "Downloaded $2"
}

# $1 - Base URL
# $2 - Base name, usually base filename
# $3 - Version      - or nonstandard filename (See $4)
# $4 - Package type - empty means nonstandard naming (See $3)
download_packet() {

  if test "x$2" = "xgtk2" || test "x$2" = "xgtk3" ; then
    BFNAME="gtk+"
  else
    BFNAME="$2"
  fi

  if test "x$4" = "xdsc" ; then
    DLFILENAME="${BFNAME}_$3.$4"

    if ! download_file "$1" "$DLFILENAME"
    then
      echo "Download of $BFNAME version $3 dsc file failed" >&2
      return 1
    fi

    FILELIST_SECTION=no
    cat "$DLDIR/$DLFILENAME" |
    ( while read PART1 PART2 PART3
      do
        if test "x$FILELIST_SECTION" = "xyes"
        then
          if test "x$PART1" = "x"
          then
            FILELIST_SECTION=no
          else
            if ! download_file "$1" "$PART3"
            then
              echo "Download of $BFNAME version $3 file $PART3 failed" >&2
              return 1
            fi
          fi
        elif test "x$PART1" = "xFiles:"
        then
          FILELIST_SECTION=yes
        fi
      done
    )
  else
    if test "x$4" = "x" ; then
      DLFILENAME="$3"
    else
      DLFILENAME="$BFNAME-$3.$4"
    fi
    if ! download_file "$1" "$DLFILENAME"
    then
       echo "Download of $BFNAME version $3 failed" >&2
       return 1
    fi
  fi
}

# $1 - Base URL
# $2 - Packet name
# $3 - Base filename
# $4 - Number of patches
download_patches_internal() {

  declare -i DLNUM=1
  declare -i DLTOTAL=$4

  while test $DLNUM -le $DLTOTAL
  do
    if test $DLNUM -lt 10 ; then
      ZEROES="00"
    else
      ZEROES="0"
    fi
    DLFILENAME="${3}${ZEROES}${DLNUM}"
    if ! download_file "$1" "$DLFILENAME" "patch"
    then
      echo "Download of $2 patch $DLNUM failed" >&2
      return 1
    fi
    DLNUM=$DLNUM+1
  done
}

# $1 - Base URL
# $2 - Base filename
# $3 - Version
# $4 - Package type
# Return:
# 0 - Downloaded
# 1 - Failure
# 2 - Not needed
download_needed() {
  if test "x$3" != "x"
  then
    PACKVER="$3"
  else
    PACKVER="$VERSION_SELECTED"
  fi

  if test "x$DOWNLOAD_PACKET" != "x" ; then
    if test "x$DOWNLOAD_PACKET" = "x$2" ; then
      download_packet "$1" "$2" "$PACKVER" "$4"
      return $?
    fi
    return 2
  fi
  if test "x$STEPLIST" = "x" ; then
    download_packet "$1" "$2" "$PACKVER" "$4"
    return $?
  fi
  for STEP in $STEPLIST
  do
    BASENAME=$2
    if belongs_to_step $BASENAME $STEP ; then
      download_packet "$1" "$2" "$PACKVER" "$4"
      return $?
    fi
  done

  echo "$2 version $PACKVER not needed, skipping"
  return 2
}

# $1 - Base URL
# $2 - Packet name
# $3 - Base filename
# $4 - Version
# $5 - Number of patches
# Return:
# 0 - Downloaded
# 1 - Failure
# 2 - Not needed
download_patches() {
  if test "x$4" != "x"
  then
    PACKVER="$4"
  else
    PACKVER="$VERSION_SELECTED"
  fi

  if test "x$DOWNLOAD_PACKET" != "x" ; then
    if test "x$DOWNLOAD_PACKET" = "x$2" ; then
      download_patches_internal "$1" "$2" "$3" "$5"
      return $?
    fi
    return 2
  fi
  if test "x$STEPLIST" = "x" ; then
    download_patches_internal "$1" "$2" "$3" "$5"
    return $?
  fi
  for STEP in $STEPLIST
  do
    if belongs_to_step $2 $STEP ; then
      download_patches_internal "$1" "$2" "$3" "$5"
      return $?
    fi
  done

  echo "$3 version $PACKVER patches not needed, skipping"
  return 2
}

CROSSER_MAINDIR="$(cd "$(dirname "$0")/.." ; pwd)"

if ! test -e "$CROSSER_MAINDIR/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

if ! . "$CROSSER_MAINDIR/scripts/helpers.sh"
then
  echo "Failed to read \"$CROSSER_MAINDIR/scripts/helpers.sh\"" >&2
  exit 1
fi

if ! . "$CROSSER_MAINDIR/scripts/packethandlers.sh"
then
  echo "Failed to read \"$CROSSER_MAINDIR/scripts/packethandlers.sh\"" >&2
  exit 1
fi

if test "x$1" = "x-h" || test "x$1" = "x--help" ; then
  HELP_RETURN=0
elif test "x$1" = "x" ; then
  HELP_RETURN=1
fi

if test "x$HELP_RETURN" != "x" ; then
  echo "Usage: $(basename "$0") <step> [versionset]"
  echo "       $(basename "$0") --packet <name> [version] [patches]"
  echo
  echo " Possible steps:"
  echo "  - win"

  exit $HELP_RETURN
fi

if test "x$1" = "x-v" || test "x$1" = "x--version"
then
  echo "Downloader for Crosser $CROSSER_VERSION"
  exit 0
fi

if test "x$1" = "x--packet"
then
  if test "x$3" != "x"
  then
    export VERSION_SELECTED="$3"
    if test "x$4" != "x" ; then
      if test "x$2" != "xreadline"
      then
        echo "Number of patches given for component which has no patches." >&2
        exit 1
      fi
      export PATCHES_SELECTED="$4"
    else
      export PATCHES_SELECTED="0"
    fi
  else
    VERSIONSET="current"
  fi
elif test "x$1" != "x--packet" && test "x$2" != "x"
then
  VERSIONSET="$2"
else
  VERSIONSET="current"
fi

if test "x$VERSIONSET" != "x"
then
  if ! test -e "$CROSSER_MAINDIR/setups/$VERSIONSET.versions"
  then
    echo "Versionset $VERSIONSET.versions not found" >&2
    exit 1
  fi

  if ! . "$CROSSER_MAINDIR/setups/$VERSIONSET.versions" ; then
    echo "Failed to read list of package versions ($VERSIONSET.versions)" >&2
    exit 1
  fi
fi

if test -e "$CROSSER_MAINDIR/mirrors.conf" ; then
  MIRRORCONF="$CROSSER_MAINDIR/mirrors.conf"
elif test -e "$HOME/.crosser.mirrors" ; then
  MIRRORCONF="$HOME/.crosser.mirrors"
fi

if test "x$MIRRORCONF" != "x" ; then
  if ! . "$MIRRORCONF" ; then
    echo "Problem in reading list of mirrors to use from $MIRRORCONF" >&2
    exit 1
  fi
fi

if ! . "$CROSSER_MAINDIR/steps/stepfuncs.sh" ; then
  echo "Problem in reading stepfuncs.sh" >&2
  exit 1
fi

if test "x$1" = "x--packet" ; then
  if test "x$2" = "x" ; then
    echo "No packet name given after --packet" >&2
    exit 1
  fi
  DOWNLOAD_PACKET="$2"
else
  STEPLIST="$(parse_steplist $1)"
  RET=$?
  if test "x$RET" != "x0"
  then
    echo "Error in step parameters \"$1\"" >&2
    exit 1
  fi
fi

if test "x$MIRROR_GNU" = "x" ; then
  MIRROR_GNU="ftp://ftp.gnu.org/gnu"
fi

if test "x$MIRROR_GCC" = "x"; then
  MIRROR_GCC="http://gcc.cybermirror.org"
fi

if test "x$MIRROR_IM" = "x" ; then
  MIRROR_IM="http://imagemagick.mirrorcatalogs.com"
fi

MIRROR_SOURCEFORGE="http://sourceforge.net"
MIRROR_GNOME="http://ftp.gnome.org/pub/gnome"
MIRROR_SAVANNAH="http://download.savannah.gnu.org"

if test "x$VERSION_SELECTED" != "x"
then
  case $DOWNLOAD_PACKET in
    zlib)        VERSION_ZLIB=$VERSION_SELECTED ;;
    bzip2)       VERSION_BZIP2=$VERSION_SELECTED ;;
    glib)        VERSION_GLIB=$VERSION_SELECTED ;;
    pango)       VERSION_PANGO=$VERSION_SELECTED ;;
    gdk-pixbuf)  VERSION_GDK_PIXBUF=$VERSION_SELECTED ;;
    gtk2)        VERSION_GTK2=$VERSION_SELECTED ;;
    gtk3)        VERSION_GTK3=$VERSION_SELECTED ;;
    gtk-engines) VERSION_GTK_ENG=$VERSION_SELECTED ;;
    atk)         VERSION_ATK=$VERSION_SELECTED ;;
    readline)    VERSION_READLINE=$VERSION_SELECTED
                 PATCHES_READLINE=$PATCHES_SELECTED ;;
    autoconf)    VERSION_AUTOCONF=$VERSION_SELECTED ;;
    automake)    VERSION_AUTOMAKE=$VERSION_SELECTED ;;
    libtool)     VERSION_LIBTOOL=$VERSION_SELECTED ;;
    jpeg)        VERSION_JPEG=$VERSION_SELECTED ;;
    sqlite)      VERSION_SQLITE=$VERSION_SELECTED ;;
    cairo)       VERSION_CAIRO=$VERSION_SELECTED ;;
    libpng)      VERSION_PNG=$VERSION_SELECTED ;;
  esac
fi

GLIB_DIR="$(echo $VERSION_GLIB | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
PANGO_DIR="$(echo $VERSION_PANGO | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GDK_PB_DIR="$(echo $VERSION_GDK_PIXBUF | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK2_DIR="$(echo $VERSION_GTK2 | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK3_DIR="$(echo $VERSION_GTK3 | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK_ENG_DIR="$(echo $VERSION_GTK_ENG | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
ATK_DIR="$(echo $VERSION_ATK | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
PNG_DIR="$(echo $VERSION_PNG | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n "libpng${MAJOR}${MINOR}"))"

READLINE_SHORT="$(echo $VERSION_READLINE | sed 's/\.//g')"

SQL_VERSTR="$(sqlite_verstr $VERSION_SQLITE)"

if is_minimum_version $VERSION_SQLITE 3.8.3
then
   SQL_SUBDIR="2014/"
elif is_minimum_version $VERSION_SQLITE 3.7.16.1
then
   SQL_SUBDIR="2013/"
else
   SQL_SUBDIR=""
fi

if is_minimum_version $VERSION_ZLIB 1.2.8
then
  ZLIB_PACK="tar.xz"
else
  ZLIB_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_PNG 1.6.0
then
  PNG_PACK="tar.xz"
else
  PNG_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_CAIRO 1.12.2
then
  CAIRO_PACK="tar.xz"
else
  CAIRO_PACK="tar.gz"
fi

if is_minimum_version $VERSION_AUTOMAKE 1.11.3
then
  AUTOMAKE_PACK="tar.xz"
else
  AUTOMAKE_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_LIBTOOL 2.2.6a
then
  LIBTOOL_PACK="tar.gz"
else
  LIBTOOL_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_AUTOCONF 2.68b
then
  AUTOCONF_PACK="tar.xz"
else
  AUTOCONF_PACK="tar.bz2"
fi

# While there's earlier .xz packaged glib version available,
# earlier crosser versions fetched them as .bz2. In case such
# an .bz2 package already exist, we don't want to download .xz
# of the same version.
if is_minimum_version $VERSION_GLIB 2.30.3
then
  GLIB_PACK="tar.xz"
else
  GLIB_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_ATK 2.4.0
then
  ATK_PACK="tar.xz"
else
  ATK_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_PANGO 1.30.0
then
  PANGO_PACK="tar.xz"
else
  PANGO_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_GTK2 2.24.9
then
  GTK2_PACK="tar.xz"
else
  GTK2_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_GTK3 3.2.0
then
  GTK3_PACK="tar.xz"
else
  GTK3_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_GDK_PIXBUF 2.24.0
then
  GDK_PB_PACK="tar.xz"
else
  GDK_PB_PACK="tar.bz2"
fi

download_needed "$MIRROR_GNU/libtool/"  "libtool"  "$VERSION_LIBTOOL"  "$LIBTOOL_PACK"
RET="$?"
download_needed "$MIRROR_GNU/autoconf/" "autoconf" "$VERSION_AUTOCONF" "$AUTOCONF_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNU/automake/" "automake" "$VERSION_AUTOMAKE" "$AUTOMAKE_PACK"
RET="$RET $?"
download_needed "http://pkgconfig.freedesktop.org/releases/" "pkg-config" "$VERSION_PKG_CONFIG" "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNU/libiconv/"                 "libiconv"   "$VERSION_ICONV"      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/projects/libpng/files/$PNG_DIR/older-releases/$VERSION_PNG/" "libpng" "$VERSION_PNG" "$PNG_PACK"
#download_needed "$MIRROR_SOURCEFORGE/projects/libpng/files/$PNG_DIR/$VERSION_PNG/" "libpng"     "$VERSION_PNG"        "$PNG_PACK"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/projects/libpng/files/zlib/$VERSION_ZLIB/" "zlib"       "$VERSION_ZLIB"       "$ZLIB_PACK"
RET="$RET $?"
download_needed "http://www.bzip.org/$VERSION_BZIP2/"   "bzip2"      "$VERSION_BZIP2"      "tar.gz"
RET="$RET $?"
download_needed "http://tukaani.org/xz/"                "xz"         "$VERSION_XZ"         "tar.xz"
RET="$RET $?"
download_needed "$MIRROR_GNU/readline/"                 "readline"   "$VERSION_READLINE"   "tar.gz"
RET="$RET $?"
download_patches "$MIRROR_GNU/readline/readline-$VERSION_READLINE-patches/" \
                 "readline"            "readline${READLINE_SHORT}-" \
                 "$VERSION_READLINE"   "$PATCHES_READLINE"
RET="$RET $?"
download_needed "$MIRROR_GNU/gettext/"                  "gettext"    "$VERSION_GETTEXT"    "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/glib/$GLIB_DIR/" "glib"       "$VERSION_GLIB"       "$GLIB_PACK"
RET="$RET $?"
download_needed "http://www.ijg.org/files/"             "jpeg"       "jpegsrc.v${VERSION_JPEG}.tar.gz"
RET="$RET $?"
download_needed "ftp://ftp.remotesensing.org/pub/libtiff/" "tiff"    "$VERSION_TIFF"       "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/projects/expat/files/$VERSION_EXPAT/" "expat"      "$VERSION_EXPAT"      "tar.gz"
RET="$RET $?"
download_needed "http://www.freedesktop.org/software/harfbuzz/release/" "harfbuzz" "$VERSION_HARFBUZZ" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_SAVANNAH/releases/freetype/"   "freetype"   "$VERSION_FREETYPE"   "tar.bz2"
RET="$RET $?"
download_needed "http://fontconfig.org/release/"        "fontconfig" "$VERSION_FONTCONFIG" "tar.gz"
RET="$RET $?"
download_needed "http://curl.haxx.se/download/"         "curl"       "$VERSION_CURL"       "tar.bz2"
RET="$RET $?"
download_needed "ftp://sourceware.org/pub/libffi/"      "libffi"     "$VERSION_FFI"        "tar.gz"
RET="$RET $?"
download_needed "http://cairographics.org/releases/"    "pixman"     "$VERSION_PIXMAN"     "tar.gz"
RET="$RET $?"
download_needed "http://cairographics.org/releases/"    "cairo"      "$VERSION_CAIRO"      "$CAIRO_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/pango/$PANGO_DIR/" "pango"    "$VERSION_PANGO"      "$PANGO_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/atk/$ATK_DIR/"   "atk"        "$VERSION_ATK"        "$ATK_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gdk-pixbuf/$GDK_PB_DIR/" "gdk-pixbuf" "$VERSION_GDK_PIXBUF"  "$GDK_PB_PACK" 
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gtk+/$GTK2_DIR/" "gtk2"       "$VERSION_GTK2"        "$GTK2_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gtk+/$GTK3_DIR/" "gtk3"       "$VERSION_GTK3"        "$GTK3_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gtk-engines/$GTK_ENG_DIR/"  "gtk-engines" "$VERSION_GTK_ENG" "tar.bz2"
RET="$RET $?"
download_needed "http://downloads.xiph.org/releases/ogg/" "libogg"   "$VERSION_OGG"        "tar.xz"
RET="$RET $?"
download_needed "http://downloads.xiph.org/releases/vorbis/" "libvorbis" "$VERSION_VORBIS" "tar.xz"
RET="$RET $?"
download_needed "http://www.libsdl.org/release/"        "SDL"        "$VERSION_SDL"        "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_image/release/" "SDL_image"  "$VERSION_SDL_IMAGE"  "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_mixer/release/" "SDL_mixer"  "$VERSION_SDL_MIXER"  "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/release/"    "SDL2"       "$VERSION_SDL2"       "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_image/release/"      "SDL2_image" "$VERSION_SDL2_IMAGE" "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_mixer/release/"      "SDL2_mixer" "$VERSION_SDL2_MIXER" "tar.gz"
RET="$RET $?"
download_needed "http://www.ferzkopp.net/Software/SDL_gfx-2.0/" "SDL_gfx" "$VERSION_SDL_GFX" "tar.gz"
RET="$RET $?"
download_needed "http://www.ferzkopp.net/Software/SDL2_gfx/"      "SDL2_gfx" "$VERSION_SDL2_GFX" "tar.gz"
RET="$RET $?" 
download_needed "http://www.libsdl.org/projects/SDL_ttf/release/" "SDL_ttf" "$VERSION_SDL_TTF" "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_ttf/release/" "SDL2_ttf" "$VERSION_SDL2_TTF" "tar.gz"
RET="$RET $?"
download_needed "http://www.sqlite.com/${SQL_SUBDIR}" "sqlite" "autoconf-${SQL_VERSTR}" "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_IM/" "ImageMagick" "$VERSION_IMAGEMAGICK" "tar.xz"
RET="$RET $?"
download_needed "ftp://xmlsoft.org/libxml2/" "libxml2" "$VERSION_XML2" "tar.gz"
RET="$RET $?"

for VALUE in $RET
do
  if test "$VALUE" = "0" ; then
    DOWNLOADED=true
  elif test "$VALUE" = "1" ; then
    FAILED=true
  fi
done

if test "x$DOWNLOAD_PACKET" != "x" && test "x$DOWNLOADED" != "xtrue" ; then
  echo "Download instructions for $DOWNLOAD_PACKET not found." >&2
  exit 1
fi

if test "x$FAILED" = "xtrue" ; then
  echo "Some packet(s) failed to download." >&2
  exit 1
fi
