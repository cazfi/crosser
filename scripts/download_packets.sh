#!/bin/bash

# download_packets.sh: Source package downloader
#
# (c) 2008-2021 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

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
    if ! mkdir -p "$DLDIR"
    then
      echo "Failed to create packet subdirectory \"$DLDIR\"" >&2
      return 1
    fi
    FLFILE="$3/$2"
  else
    DLDIR="."
    FLFILE="$2"
  fi

  TIMEPART=$(date +%y%m%d%H%M)

  if test -f filelist.txt
  then
    if grep ": $FLFILE\$" filelist.txt > /dev/null
    then
      sed "s,: .* : $FLFILE\$,: $TIMEPART : $FLFILE," filelist.txt > filelist.tmp
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
    echo "$TIMEPART : $TIMEPART : $FLFILE" >> filelist.txt
  fi

  if test -f "$DLDIR/$2"
  then
    if test "x$DLDIR" != "x."
    then
      echo "Already has $DLDIR/$2, skipping"
    else
      echo "Already has $2, skipping"
    fi
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
# $5 - Alternative Base URL
# $6 - Subdirectory to download to
download_packet() {

  BFNAME=$(component_name_to_package_name $2 $3)

  if test "x$4" = "x" ; then
    DLFILENAME="$3"
  else
    DLFILENAME="$BFNAME-$3.$4"
  fi
  if ! download_file "$1" "$DLFILENAME" "$6"
  then
    if test "x$5" = "x" || ! download_file "$5" "$DLFILENAME" "$6"
    then
      if test "x$4" != "x"
      then
        echo "Download of $BFNAME version $3 failed" >&2
      else
        echo "Download of $3 failed" >&2
      fi
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
# $5 - Alt Base URL
# $6 - Subdirectory to download to
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
  if test "x$PACKVER" = "x0" ; then
    echo "$2 disabled, not downloading."
    return 2
  fi

  if test "x$DOWNLOAD_PACKET" != "x" ; then
    if test "x$DOWNLOAD_PACKET" = "x$2" ; then
      download_packet "$1" "$2" "$PACKVER" "$4" "$5" "$6"
      return $?
    fi
    return 2
  fi
  if test "x$STEPLIST" = "x" ; then
    download_packet "$1" "$2" "$PACKVER" "$4" "$5" "$6"
    return $?
  fi
  for STEP in $STEPLIST
  do
    BASENAME=$2
    if belongs_to_step $BASENAME $STEP ; then
      download_packet "$1" "$2" "$PACKVER" "$4" "$5" "$6"
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

  if test "x$PACKVER" = "x0"
  then
      return 2
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

# $1 - Version number
major.minor_from_version()
{
  if test "x$1" = "x" ; then
    DIRVER=$VERSION_SELECTED
  else
    DIRVER=$1
  fi

  echo $DIRVER | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n "$MAJOR.$MINOR")
}

# $1 - Version number
major_from_version()
{
  if test "x$1" = "x" ; then
    DIRVER=$VERSION_SELECTED
  else
    DIRVER=$1
  fi

  echo $DIRVER | sed 's/\./ /g' | (read MAJOR REST ; echo -n "$MAJOR")
}

CROSSER_MAINDIR="$(cd "$(dirname "$0")/.." ; pwd)"

if ! test -e "$CROSSER_MAINDIR/CrosserVersion" && test -e "/usr/share/crosser/CrosserVersion"
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
  echo "Usage: $(basename "$0") <step> [versionset] [setup]"
  echo "       $(basename "$0") --packet <name> [version] [patches]"
  echo
  echo " Possible steps:"
  echo "  - win,sdl2,sfml,full"

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
    CROSSER_VERSIONSET="current"
  fi
elif test "x$1" != "x--packet"
then
  if test "x$2" != "x"
  then
    CROSSER_VERSIONSET="$2"
  else
    CROSSER_VERSIONSET="current"
  fi
  if test "x$3" != "x"
  then
    CROSSER_SETUP="$3"
  fi
else
  CROSSER_VERSIONSET="current"
fi

if test "x$CROSSER_VERSIONSET" != "x"
then
  if ! test -e "$CROSSER_MAINDIR/setups/${CROSSER_VERSIONSET}.versions"
  then
    echo "Versionset ${CROSSER_VERSIONSET}.versions not found" >&2
    exit 1
  fi

  if ! . "$CROSSER_MAINDIR/setups/${CROSSER_VERSIONSET}.versions" ; then
    echo "Failed to read list of package versions (${CROSSER_VERSIONSET}.versions)" >&2
    exit 1
  fi
fi

if test "x$CROSSER_SETUP" != "x"
then
  if ! test -e "$CROSSER_MAINDIR/setups/${CROSSER_SETUP}.conf"
  then
    echo "Setup ${CROSSER_SETUP}.conf not found" >&2
    exit 1
  fi

  if ! . "$CROSSER_MAINDIR/setups/${CROSSER_SETUP}.conf" ; then
    echo "Failed to read setup (${CROSSER_SETUP}.conf)" >&2
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

if test "x$MIRROR_IM" = "x" ; then
  MIRROR_IM="http://www.imagemagick.org/download/releases"
fi

MIRROR_SOURCEFORGE="http://sourceforge.net"
MIRROR_GNOME="http://ftp.gnome.org/pub/gnome"
MIRROR_SAVANNAH="http://download.savannah.gnu.org"

if test "x$VERSION_SELECTED" != "x"
then
  case $DOWNLOAD_PACKET in
    zlib)        VERSION_ZLIB=$VERSION_SELECTED ;;
    glib)        VERSION_GLIB=$VERSION_SELECTED ;;
    pango)       VERSION_PANGO=$VERSION_SELECTED ;;
    graphene)    VERSION_GRAPHENE=$VERSION_SELECTED ;;
    gobject-introspection) VERSION_GOBJ_INTRO=$VERSION_SELECTED ;;
    gdk-pixbuf)  VERSION_GDK_PIXBUF=$VERSION_SELECTED ;;
    gtk3)        VERSION_GTK3=$VERSION_SELECTED ;;
    gtk4)        VERSION_GTK4=$VERSION_SELECTED ;;
    gtk-doc)     VERSION_GTK_DOC=$VERSION_SELECTED ;;
    atk)         VERSION_ATK=$VERSION_SELECTED ;;
    PDCurses)    VERSION_PDCURSES=$VERSION_SELECTED ;;
    readline)    VERSION_READLINE=$VERSION_SELECTED
                 PATCHES_READLINE=$PATCHES_SELECTED ;;
    autoconf)    VERSION_AUTOCONF=$VERSION_SELECTED ;;
    automake)    VERSION_AUTOMAKE=$VERSION_SELECTED ;;
    libtool)     VERSION_LIBTOOL=$VERSION_SELECTED ;;
    gettext)     VERSION_GETTEXT=$VERSION_SELECTED ;;
    jpeg)        VERSION_JPEG=$VERSION_SELECTED ;;
    sqlite)      VERSION_SQLITE=$VERSION_SELECTED ;;
    cairo)       VERSION_CAIRO=$VERSION_SELECTED ;;
    qt5)         VERSION_QT5=$VERSION_SELECTED ;;
    tinycthread) VERSION_TCT=$VERSION_SELECTED ;;
    icu4c)       VERSION_ICU=$VERSION_SELECTED ;;
    libpng)      VERSION_PNG=$VERSION_SELECTED ;;
    hicolor-icon-theme) VERSION_HICOLOR=$VERSION_SELECTED ;;
    libepoxy)    VERSION_LIBEPOXY=$VERSION_SELECTED ;;
    pcre2)       VERSION_PCRE2=$VERSION_SELECTED ;;
    sfml)        VERSION_SFML=$VERSION_SELECTED ;;
    fribidi)     VERSION_FRIBIDI=$VERSION_SELECTED ;;
    meson)       VERSION_MESON=$VERSION_SELECTED ;;
    harfbuzz)    VERSION_HARFBUZZ=$VERSION_SELECTED ;;
    freetype)    VERSION_FREETYPE=$VERSION_SELECTED ;;
    shared-mime-info) VERSION_SHARED_MIME_INFO=$VERSION_SELECTED ;;
    libffi)      VERSION_FFI=$VERSION_SELECTED ;;
    jansson)     VERSION_JANSSON=$VERSION_SELECTED ;;
  esac
fi

GLIB_DIR="$(echo $VERSION_GLIB | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK_DOC_DIR="$(echo $VERSION_GTK_DOC | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GOBJ_INTRO_DIR="$(echo $VERSION_GOBJ_INTRO | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
PANGO_DIR="$(echo $VERSION_PANGO | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GRAPHENE_DIR="$(echo $VERSION_GRAPHENE | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GDK_PB_DIR="$(echo $VERSION_GDK_PIXBUF | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK3_DIR="$(echo $VERSION_GTK3 | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
GTK4_DIR="$(echo $VERSION_GTK4 | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
if is_smaller_version $VERSION_ADWAITA_ICON 40.0 ; then
  ADWAITA_ICON_DIR="$(major.minor_from_version $VERSION_ADWAITA_ICON)"
else
  ADWAITA_ICON_DIR="$(major_from_version $VERSION_ADWAITA_ICON)"
fi
CROCO_DIR="$(major.minor_from_version $VERSION_CROCO)"
LIBEPOXY_DIR="$(echo $VERSION_LIBEPOXY | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
ATK_DIR="$(echo $VERSION_ATK | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR ))"
PNG_DIR="$(echo $VERSION_PNG | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n "libpng${MAJOR}${MINOR}"))"
QT5_DIR="$(echo $VERSION_QT5 | sed 's/\./ /g' | (read MAJOR MINOR PATCH ; echo -n $MAJOR.$MINOR))"
ICU_DIR="release-$(echo $VERSION_ICU | sed 's/\./-/')"
ICU_FILEVER="$(icu_filever $VERSION_ICU)"

READLINE_SHORT="$(echo $VERSION_READLINE | sed 's/\.//g')"
if echo "$VERSION_READLINE" | grep "\-rc" >/dev/null
then
    RL_SUBDIR="bash"
else
    RL_SUBDIR="readline"
fi

SQL_VERSTR="$(sqlite_verstr $VERSION_SQLITE)"

if is_minimum_version $VERSION_SQLITE 3.34.1
then
  SQL_SUBDIR="2021/"
elif is_minimum_version $VERSION_SQLITE 3.31.0
then
  SQL_SUBDIR="2020/"
elif is_minimum_version $VERSION_SQLITE 3.27.0
then
  SQL_SUBDIR="2019/"
elif is_minimum_version $VERSION_SQLITE 3.22.0
then
  SQL_SUBDIR="2018/"
else
  SQL_SUBDIR=""
fi

if is_minimum_version $VERSION_FRIBIDI 1.0.9
then
  FRIBIDI_PACK="tar.xz"
else
  FRIBIDI_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_ZLIB 1.2.8
then
  ZLIB_PACK="tar.xz"
else
  ZLIB_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_CAIRO 1.12.2
then
  CAIRO_PACK="tar.xz"
else
  CAIRO_PACK="tar.gz"
fi

if is_minimum_version $VERSION_AUTOCONF 2.68b
then
  AUTOCONF_PACK="tar.xz"
else
  AUTOCONF_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_PANGO 1.30.0
then
  PANGO_PACK="tar.xz"
else
  PANGO_PACK="tar.bz2"
fi

if is_minimum_version $VERSION_GETTEXT 0.19.1
then
  GETTEXT_PACK="tar.xz"
else
  GETTEXT_PACK="tar.gz"
fi

if is_minimum_version $VERSION_HICOLOR 0.14
then
  HICOLOR_PACK="tar.xz"
else
  HICOLOR_PACK="tar.gz"
fi

if is_minimum_version $VERSION_FREETYPE 2.10.1
then
  FT_PACK="tar.xz"
else
  FT_PACK="tar.bz2"
fi

if echo $VERSION_QT5 | grep alpha >/dev/null ||
   echo $VERSION_QT5 | grep beta >/dev/null ||
   echo $VERSION_QT5 | grep rc >/dev/null
then
    QT5_RELEASEDIR="development_releases"
else
    QT5_RELEASEDIR="official_releases"
fi

download_needed "$MIRROR_GNU/libtool/"  "libtool"  "$VERSION_LIBTOOL"  "tar.xz"
RET="$?"
download_needed "$MIRROR_GNU/autoconf/" "autoconf" "$VERSION_AUTOCONF" "$AUTOCONF_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNU/automake/" "automake" "$VERSION_AUTOMAKE" "tar.xz"
RET="$RET $?"
download_needed "http://pkgconfig.freedesktop.org/releases/" "pkg-config" "$VERSION_PKG_CONFIG" "tar.gz"
RET="$RET $?"
download_needed "https://github.com/pkgconf/pkgconf/archive/" "pkgconf" "$VERSION_PKGCONF" "tar.gz"
RET="$RET $?"
download_needed "https://github.com/fribidi/fribidi/releases/download/v${VERSION_FRIBIDI}/" "fribidi" "$VERSION_FRIBIDI" "$FRIBIDI_PACK"
RET="$RET $?"
download_needed "http://tango.freedesktop.org/releases/" "icon-naming-utils" "$VERSION_ICON_NUTILS" "tar.bz2"
RET="$RET $?"
download_needed "http://tango.freedesktop.org/releases/" "tango-icon-theme" "$VERSION_TANGO_ICONS" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNU/libiconv/"                 "libiconv"   "$VERSION_ICONV"      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/projects/libpng/files/$PNG_DIR/$VERSION_PNG/" "libpng" "$VERSION_PNG" "tar.xz" \
                "$MIRROR_SOURCEFORGE/projects/libpng/files/$PNG_DIR/older-releases/$VERSION_PNG/"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/projects/libpng/files/zlib/$VERSION_ZLIB/" "zlib"       "$VERSION_ZLIB"       "$ZLIB_PACK"
RET="$RET $?"
download_needed "https://github.com/PhilipHazel/pcre2/releases/download/pcre-$VERSION_PCRE2" "pcre2" "$VERSION_PCRE2" "tar.bz2" "https://ftp.pcre.org/pub/pcre/"
RET="$RET $?"
download_needed "http://tukaani.org/xz/"                "xz"         "$VERSION_XZ"         "tar.xz"
RET="$RET $?"
download_needed "$MIRROR_SOURCEFORGE/projects/pdcurses/files/pdcurses/$VERSION_PDCURSES/" "PDCurses"      "$VERSION_PDCURSES"      "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_GNU/${RL_SUBDIR}/"             "readline"   "$VERSION_READLINE"   "tar.gz"
RET="$RET $?"
download_patches "$MIRROR_GNU/readline/readline-$VERSION_READLINE-patches/" \
                 "readline"            "readline${READLINE_SHORT}-" \
                 "$VERSION_READLINE"   "$PATCHES_READLINE"
RET="$RET $?"
download_needed "$MIRROR_GNU/gettext/"                  "gettext"    "$VERSION_GETTEXT"    "$GETTEXT_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/glib/$GLIB_DIR/" "glib"       "$VERSION_GLIB"       "tar.xz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gtk-doc/$GTK_DOC_DIR/" "gtk-doc" "$VERSION_GTK_DOC" "tar.xz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gobject-introspection/$GOBJ_INTRO_DIR/" "gobject-introspection" "$VERSION_GOBJ_INTRO" "tar.xz"
RET="$RET $?"
download_needed "http://www.ijg.org/files/"             "jpeg"       "jpegsrc.v${VERSION_JPEG}.tar.gz"
RET="$RET $?"
download_needed "http://download.osgeo.org/libtiff/"    "tiff"    "$VERSION_TIFF"       "tar.gz"
RET="$RET $?"
download_needed "https://github.com/harfbuzz/harfbuzz/archive/" "harfbuzz" "$VERSION_HARFBUZZ.tar.gz" "" "" "harfbuzz"
RET="$RET $?"
download_needed "$MIRROR_SAVANNAH/releases/freetype/"   "freetype"   "$VERSION_FREETYPE"   "$FT_PACK"
RET="$RET $?"
download_needed "http://fontconfig.org/release/"        "fontconfig" "$VERSION_FONTCONFIG" "tar.gz"
RET="$RET $?"
download_needed "http://curl.haxx.se/download/"         "curl"       "$VERSION_CURL"       "tar.bz2"
RET="$RET $?"
download_needed "https://github.com/libffi/libffi/releases/download/v$VERSION_FFI/" "libffi" "$VERSION_FFI" "tar.gz"
RET="$RET $?"
download_needed "http://cairographics.org/releases/"    "pixman"     "$VERSION_PIXMAN"     "tar.gz"
RET="$RET $?"
download_needed "http://cairographics.org/releases/"    "cairo"      "$VERSION_CAIRO"      "$CAIRO_PACK" "http://cairographics.org/snapshots/"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/pango/$PANGO_DIR/" "pango"    "$VERSION_PANGO"      "$PANGO_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/graphene/$GRAPHENE_DIR/" "graphene" "$VERSION_GRAPHENE" "tar.xz"
RET="$RET $?"
download_needed "http://xkbcommon.org/download/" "libxkbcommon" "$VERSION_XKBCOMMON" "tar.xz"
RET="$RET $?"
download_needed "http://xorg.freedesktop.org/releases/individual/util/" "util-macros" "$VERSION_UTIL_MACROS" "tar.bz2"
RET="$RET $?"
download_needed "https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/$VERSION_SHARED_MIME_INFO/" "shared-mime-info" "$VERSION_SHARED_MIME_INFO" "tar.bz2"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/libepoxy/$LIBEPOXY_DIR/" "libepoxy" "$VERSION_LIBEPOXY" "tar.xz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/atk/$ATK_DIR/"   "atk"        "$VERSION_ATK"        "tar.xz"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gdk-pixbuf/$GDK_PB_DIR/" "gdk-pixbuf" "$VERSION_GDK_PIXBUF"  "tar.xz" 
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/gtk+/$GTK3_DIR/" "gtk3"       "$VERSION_GTK3"        "tar.xz"
RET="$RET $?"
if is_minimum_version "$VERSION_GTK4" 3.96 ; then
download_needed "$MIRROR_GNOME/sources/gtk/$GTK4_DIR/"  "gtk4"       "$VERSION_GTK4"        "tar.xz"
RET="$RET $?"
else
download_needed "$MIRROR_GNOME/sources/gtk+/$GTK4_DIR/" "gtk4"       "$VERSION_GTK4"        "tar.xz"
RET="$RET $?"
fi
download_needed "$MIRROR_GNOME/sources/libcroco/$CROCO_DIR/" "libcroco" "$VERSION_CROCO" "tar.xz"
RET="$RET $?"
download_needed "icon-theme.freedesktop.org/releases/" "hicolor-icon-theme" "$VERSION_HICOLOR" "$HICOLOR_PACK"
RET="$RET $?"
download_needed "$MIRROR_GNOME/sources/adwaita-icon-theme/$ADWAITA_ICON_DIR/" "adwaita-icon-theme" "$VERSION_ADWAITA_ICON" "tar.xz"
RET="$RET $?"
download_needed "http://downloads.xiph.org/releases/ogg/" "libogg"   "$VERSION_OGG"        "tar.xz"
RET="$RET $?"
download_needed "http://downloads.xiph.org/releases/vorbis/" "libvorbis" "$VERSION_VORBIS" "tar.xz"
RET="$RET $?"
download_needed "http://www.libsdl.org/release/"    "SDL2"       "$VERSION_SDL2"       "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_image/release/"      "SDL2_image" "$VERSION_SDL2_IMAGE" "tar.gz"
RET="$RET $?"
download_needed "http://www.libsdl.org/projects/SDL_mixer/release/"      "SDL2_mixer" "$VERSION_SDL2_MIXER" "tar.gz"
RET="$RET $?"
download_needed "http://www.ferzkopp.net/Software/SDL2_gfx/"      "SDL2_gfx" "$VERSION_SDL2_GFX" "tar.gz"
RET="$RET $?" 
download_needed "http://www.libsdl.org/projects/SDL_ttf/release/" "SDL2_ttf" "$VERSION_SDL2_TTF" "tar.gz"
RET="$RET $?"
download_needed "http://www.sfml-dev.org/files/" "sfml" "SFML-$VERSION_SFML-sources.zip"
RET="$RET $?"
download_needed "http://kcat.strangesoft.net/openal-releases/" "openal-soft" "$VERSION_OPENAL" "tar.bz2"
RET="$RET $?"
download_needed "http://www.ffmpeg.org/releases/" "ffmpeg" "$VERSION_FFMPEG" "tar.xz"
RET="$RET $?"
download_needed "http://www.sqlite.com/${SQL_SUBDIR}" "sqlite" "autoconf-${SQL_VERSTR}" "tar.gz"
RET="$RET $?"
download_needed "$MIRROR_IM/" "ImageMagick" "$VERSION_IMAGEMAGICK" "tar.xz"
RET="$RET $?"
download_needed "ftp://xmlsoft.org/libxml2/" "libxml2" "$VERSION_XML2" "tar.gz"
RET="$RET $?"
download_needed "https://github.com/akheron/jansson/releases/download/v${VERSION_JANSSON}/" "jansson" "$VERSION_JANSSON" "tar.bz2"
RET="$RET $?"
download_needed "https://github.com/tinycthread/tinycthread/archive/refs/tags/" "tinycthread" "v$VERSION_TCT.tar.gz" "" "" "tinycthread"
RET="$RET $?"
download_needed "https://github.com/unicode-org/icu/releases/download/$ICU_DIR/" "icu4c" "icu4c-$ICU_FILEVER-src.tgz"
RET="$RET $?"
download_needed "http://download.qt.io/$QT5_RELEASEDIR/qt/$QT5_DIR/$VERSION_QT5/single/" "qt5" "$VERSION_QT5" "tar.xz" \
		"http://download.qt.io/archive/qt/$QT_DIR/$VERSION_QT5/single/"
RET="$RET $?"
download_needed "https://github.com/mesonbuild/meson/archive/" "meson" "$VERSION_MESON.tar.gz" "" "" "meson"
RET="$RET $?"

for VALUE in $RET
do
  if test "$VALUE" = "0" ; then
    DOWNLOADED=true
  elif test "$VALUE" = "1" ; then
    FAILED=true
  fi
done

if test "x$DOWNLOAD_PACKET" != "x" && test "x$DOWNLOADED" != "xtrue" &&
   test "x$FAILED" != "xtrue" ; then
  echo "Download instructions for $DOWNLOAD_PACKET not found." >&2
  exit 1
fi

if test "x$FAILED" = "xtrue" ; then
  echo "Some packet(s) failed to download." >&2
  exit 1
fi
