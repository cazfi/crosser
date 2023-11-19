#!/bin/bash

# dllstack.sh: Cross-compile set of libraries for Windows target.
#
# (c) 2008-2023 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.
#

#############################################################################################
#
# Preparations
#

CROSSER_MAINDIR="$(cd "$(dirname "$0")" || exit 1 ; pwd)"

if ! test -e "${CROSSER_MAINDIR}/CrosserVersion" && test -e "/usr/share/crosser/CrosserVersion"
then
  CROSSER_MAINDIR="/usr/share/crosser"
fi

if test "$1" = "-h" || test "$1" = "--help"
then
  echo "Usage: $(basename "$0") [[-h|--help]|[-v|--version]|[install prefix]] [versionset] [setup]"
  exit 0
fi

# In order to give local setup opportunity to override versions,
# we have to load versionset before setup_reader.sh
# helpers.sh requires environment to be set up by setup_reader.sh.
if test "$2" != "" ; then
  CROSSER_VERSIONSET="$2"
else
  CROSSER_VERSIONSET="current"
fi
if test -e "${CROSSER_MAINDIR}/setups/${CROSSER_VERSIONSET}.versions"
then
  . "${CROSSER_MAINDIR}/setups/${CROSSER_VERSIONSET}.versions"
else
  # Versions being unset do not prevent loading of setup_reader.sh and helper.sh,
  # resulting environment would just be unusable for building.
  # We are not going to build anything, but just issuing error message - and for
  # that we read log_error from helpers.sh
  CROSSER_ERR_MSG="Cannot find versionset \"${CROSSER_VERSIONSET}.versions\""
fi

. "${CROSSER_MAINDIR}/scripts/setup_reader.sh"
. "${CROSSER_MAINDIR}/scripts/helpers.sh"
. "${CROSSER_MAINDIR}/scripts/packethandlers.sh"

# This must be after reading helpers.sh so that ${CROSSER_VERSION} is set
if test "$1" = "-v" || test "$1" = "--version"
then
  echo "Windows library stack builder for Crosser ${CROSSER_VERSION}"
  exit 0
fi

if test "$3" = ""
then
  CROSSER_SETUP="${CROSSER_DEFAULT_SETUP}"
else
  CROSSER_SETUP="$3"
fi

if ! log_init
then
  echo "Cannot setup logging!" >&2
  exit 1
fi

if test "${CROSSER_ERR_MSG}" != ""
then
  log_error "${CROSSER_ERR_MSG}"
  exit 1
fi

if test "$1" != ""
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
  if test "$3" = "pkg-config"
  then
    BTYPE="$3"
    BDTYPE="cross"
  else
    if test "$3" != ""
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

  if test "$BERR" = "true"
  then
    return 1
  fi
}

# $1   - Build dir or 'src'
# $2   - Component
# $3   - Extra configure options
# [$4] - Build type ('native' | 'windres' | 'cross' |
#                    'qt' | 'pkg-config' | 'custom' |
#                    'unicode' | 'nounicode')
#        Of these, either 'unicode' or 'nounicode' is also the default,
#        but if you really want one of them, make it explicit.
# [$5] - Src subdir
# [$6] - Make options
# [$7] - Version
# [$8] - 'yes' - build default target before 'install'
build_component_full()
{
  log_packet "$2"

  if test "$7" != ""
  then
    BVER="$7"
  else
    BVER="$(component_version "$2")"
  fi

  if test "${BVER}" = ""
  then
    log_error "Version for $2 not defined"
    return 1
  fi

  if test "${BVER}" = "0"
  then
    return 0
  fi

  BNAME=$(component_name_to_package_name "$2" "${BVER}")

  if test "$5" != ""
  then
    SUBDIR="$5"
    if ! test -d "${CROSSER_SRCDIR}/${SUBDIR}"
    then
      log_error "${BNAME} srcdir \"$5\" doesn't exist"
      return 1
    fi
  else
    SUBDIR="$(src_subdir "${BNAME}" "${BVER}")"
    if test "${SUBDIR}" = ""
    then
      log_error "Cannot find srcdir for ${BNAME} version ${BVER}"
      return 1
    fi
  fi

  if test "$1" != "src"
  then
    DISPLAY_NAME="$1"
    BUILDDIR="${CROSSER_BUILDDIR}/$1"
    if ! mkdir -p "${BUILDDIR}"
    then
      log_error "Failed to create directory ${BUILDDIR}"
      return 1
    fi
    SRCDIR="${CROSSER_SRCDIR}/${SUBDIR}"
  else
    DISPLAY_NAME="$2"
    BUILDDIR="${CROSSER_SRCDIR}/${SUBDIR}"
    SRCDIR="."
  fi

  (
  cd "$BUILDDIR"

  if test "$4" = "native"
  then
    CONFOPTIONS="--prefix=${NATIVE_PREFIX} $3"
    unset CPPFLAGS
    unset LDFLAGS
    export PKG_CONFIG_PATH="${NATIVE_PKG_CONFIG_PATH}"
  elif test "$4" = "cross"
  then
    CONFOPTIONS="--prefix=${NATIVE_PREFIX} --build=${CROSSER_BUILD_ARCH} --host=${CROSSER_BUILD_ARCH} --target=${CROSSER_TARGET} $3"
    unset CPPFLAGS
    unset LDFLAGS
    export PKG_CONFIG_PATH="${NATIVE_PKG_CONFIG_PATH}"
  elif test "$4" = "pkg-config"
  then
    CONFOPTIONS="--prefix=${DIST_NATIVE_PREFIX} --program-prefix=${CROSSER_TARGET}- $3"
    unset CPPFLAGS
    unset LDFLAGS
    export PKG_CONFIG_PATH="${NATIVE_PKG_CONFIG_PATH}"
  elif test "$4" = "custom"
  then
    CONFOPTIONS="$3"
    unset CPPFLAGS
    unset LDFLAGS
  elif test "$4" = "windres"
  then
    CONFOPTIONS="--prefix=${DLLSPREFIX} --build=${CROSSER_BUILD_ARCH} --host=${CROSSER_TARGET} --target=${CROSSER_TARGET} $3"
    unset CPPFLAGS
    export LDFLAGS="-L${DLLSPREFIX}/lib -static-libgcc ${CROSSER_STDCXX}"
    export CC="${CROSSER_TARGET}-gcc${TARGET_SUFFIX} -static-libgcc"
    export CXX="${CROSSER_TARGET}-g++${TARGET_SUFFIX} ${CROSSER_STDCXX} -static-libgcc"
  elif test "$4" = "qt"
  then
    CONFOPTIONS="-prefix ${DLLSPREFIX} $3"
  else
    CONFOPTIONS="--prefix=${DLLSPREFIX} --build=${CROSSER_BUILD_ARCH} --host=${CROSSER_TARGET} --target=${CROSSER_TARGET} $3"
    export CPPFLAGS="-I${DLLSPREFIX}/include -I${TGT_HEADERS} ${CROSSER_WINVER_FLAG}"
    # Default is 'nounicode'. To change that, make this check
    # ' "$4" != "nounicode" '
    if test "$4" = "unicode" ; then
      CPPFLAGS="${CPPFLAGS} -DUNICODE"
    fi
    export LDFLAGS="-L${DLLSPREFIX}/lib -static-libgcc ${CROSSER_STDCXX}"
    export CC="${CROSSER_TARGET}-gcc${TARGET_SUFFIX} -static-libgcc"
    export CXX="${CROSSER_TARGET}-g++${TARGET_SUFFIX} ${CROSSER_STDCXX} -static-libgcc"
    export PKG_CONFIG_PATH="${DLLSPREFIX}/lib/${CROSSER_PKG_ARCH}/pkgconfig"
  fi

  if test -x "${SRCDIR}/configure"
  then
    log_write 1 "Configuring ${DISPLAY_NAME}"
    log_write 3 "  Options: \"${CONFOPTIONS}\""
    log_flags

    if ! "${SRCDIR}/configure" ${CONFOPTIONS} \
         >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "Configure for ${DISPLAY_NAME} failed"
      return 1
    fi
  elif test -f "${SRCDIR}/CMakeLists.txt"
  then
    CONFOPTIONS="-DCMAKE_TOOLCHAIN_FILE=${DLLSPREFIX}/etc/toolchain.cmake -DCMAKE_PREFIX_PATH=${DLLSPREFIX} -DCMAKE_SYSTEM_NAME=Windows -DHOST=${CROSSER_TARGET} -DCMAKE_INSTALL_PREFIX=${DLLSPREFIX} ${CONFOPTIONS}"

    log_write 1 "Configuring ${DISPLAY_NAME}"
    log_write 3 "  Options: \"${CONFOPTIONS}\""
    log_flags

    if ! cmake $CONFOPTIONS "${SRCDIR}" \
           >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "CMake configure for ${DISPLAY_NAME} failed"
      return 1
    fi
  fi

  log_write 1 "Building ${DISPLAY_NAME}"

  if test -f Makefile
  then
    if test "$8" = "yes"
    then
      log_write 3 "  Make targets: [default] install"
    else
      log_write 3 "  Make targets: install"
    fi
    if test "$6" = "no"
    then
      MAKEOPTIONS=""
    elif test "$6" != ""
    then
      MAKEOPTIONS="$6"
    else
      MAKEOPTIONS="${CROSSER_COREOPTIONS}"
    fi
    log_write 4 "  Options: \"${MAKEOPTIONS}\""

    if test "$8" = "yes"
    then
      if ! make ${MAKEOPTIONS} >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
      then
        log_error "Make for ${DISPLAY_NAME} failed"
        return 1
      fi
    fi

    if ! make ${MAKEOPTIONS} install >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
    then
      log_error "Install for ${DISPLAY_NAME} failed"
      return 1
    fi
  else
    log_error "Can't detect build method for ${DISPLAY_NAME}"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "${DISPLAY_NAME} : ${BVER}" >> "${DLLSPREFIX}/ComponentVersions.txt"
  fi

  return $RET
}

# $1 - Component
# $2 - Extra cmake options
build_with_cmake()
{
  build_with_cmake_full "$1" "$1" "$2"
}

# $1   - Build dir
# $2   - Component
# $3   - Extra configure options
# [$4] - Build type ('native-qt6', 'qt', 'custom')
# [$5] - Src subdir
build_with_cmake_full()
{
  log_packet "$2"

  BVER="$(component_version "$2")"

  if test "${BVER}" = ""
  then
    log_error "Version for $2 not defined"
    return 1
  fi

  if test "${BVER}" = "0"
  then
    return 0
  fi

  BNAME=$(component_name_to_package_name "$2" "${BVER}")

  if test "$5" != ""
  then
    SUBDIR="$5"
    if ! test -d "${CROSSER_SRCDIR}/${SUBDIR}"
    then
      log_error "${BNAME} srcdir \"$5\" doesn't exist"
      return 1
    fi
  else
    SUBDIR="$(src_subdir "${BNAME}" "${BVER}")"
    if test "${SUBDIR}" = ""
    then
      log_error "Cannot find srcdir for ${BNAME} version ${BVER}"
      return 1
    fi
  fi

  DISPLAY_NAME="$1"
  BUILDDIR="${CROSSER_BUILDDIR}/$1"
  if ! mkdir -p "${BUILDDIR}"
  then
    log_error "Failed to create directory ${BUILDDIR}"
    return 1
  fi
  SRCDIR="${CROSSER_SRCDIR}/${SUBDIR}"

  (
  cd "${BUILDDIR}" || return 1

  if test "$4" = "native-qt6"
  then
    CONFOPTIONS="--prefix=${DIST_NATIVE_PREFIX} $3"
    unset CPPFLAGS
    unset LDFLAGS
    export PKG_CONFIG_PATH="${NATIVE_PKG_CONFIG_PATH}"
  elif test "$4" = "qt"
  then
    CONFOPTIONS="-prefix ${DLLSPREFIX} $3"
  elif test "$4" = "custom"
  then
    CONFOPTIONS="$3"
    unset CPPFLAGS
    unset LDFLAGS
  else
    CONFOPTIONS="$3"
    export CPPFLAGS="-I${DLLSPREFIX}/include -I${TGT_HEADERS} ${CROSSER_WINVER_FLAG}"
    export LDFLAGS="-L${DLLSPREFIX}/lib -static-libgcc ${CROSSER_STDCXX}"
    export CC="${CROSSER_TARGET}-gcc${TARGET_SUFFIX} -static-libgcc"
    export CXX="${CROSSER_TARGET}-g++${TARGET_SUFFIX} ${CROSSER_STDCXX} -static-libgcc"
    export PKG_CONFIG_PATH="${DLLSPREFIX}/lib/${CROSSER_PKG_ARCH}/pkgconfig"
  fi

  log_write 1 "Configuring ${DISPLAY_NAME}"
  log_write 3 "  Options: \"${CONFOPTIONS}\""
  log_flags

  if test -x "${SRCDIR}/configure" &&
     (test "$4" = "native-qt6" || test "$4" = "qt" )
  then
    if ! "${SRCDIR}/configure" ${CONFOPTIONS} \
         >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "Configure for ${DISPLAY_NAME} failed"
      return 1
    fi
  else
    CONFOPTIONS="-DCMAKE_TOOLCHAIN_FILE=${DLLSPREFIX}/etc/toolchain.cmake -DCMAKE_PREFIX_PATH=${DLLSPREFIX} -DCMAKE_SYSTEM_NAME=Windows -DHOST=${CROSSER_TARGET} -DCMAKE_INSTALL_PREFIX=${DLLSPREFIX} ${CONFOPTIONS}"

    if ! cmake ${CONFOPTIONS} "${SRCDIR}" \
           >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "CMake configure for ${DISPLAY_NAME} failed"
      return 1
    fi
  fi

  log_write 1 "Building ${DISPLAY_NAME}"

  if test -f CMakeCache.txt
  then
    if ! cmake --build . --parallel \
         >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "CMake build for ${DISPLAY_NAME} failed"
      return 1
    fi
    if ! cmake --install . \
         >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "CMake install for ${DISPLAY_NAME} failed"
      return 1
    fi
  elif test -f Makefile
  then
    log_write 3 "  Make targets: [default] install"

    MAKEOPTIONS="${CROSSER_COREOPTIONS}"
    log_write 4 "  Options: \"${MAKEOPTIONS}\""

    if ! make ${MAKEOPTIONS} \
         >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "Make for ${DISPLAY_NAME} failed"
      return 1
    fi

    if ! make ${MAKEOPTIONS} install \
         >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "Install for ${DISPLAY_NAME} failed"
      return 1
    fi
  else
    log_error "Can't detect build method for ${DISPLAY_NAME}"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "${DISPLAY_NAME} : ${BVER}" >> "${DLLSPREFIX}/ComponentVersions.txt"
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

  BVER="$(component_version $2)"

  if test "${BVER}" = ""
  then
    log_error "Version for $2 not defined"
    return 1
  fi

  if test "${BVER}" = "0"
  then
    return 0
  fi

  BNAME="$(component_name_to_package_name $2 "${BVER}")"

  SUBDIR="$(src_subdir $BNAME $BVER)"
  if test "${SUBDIR}" = ""
  then
    log_error "Cannot find srcdir for ${BNAME} version ${BVER}"
    return 1
  fi
  if test "$5" != "" ; then
    SUBDIR="${SUBDIR}/$5"
    if ! test -d "${CROSSER_SRCDIR}/${SUBDIR}" ; then
      log_error "Cannot find source subdir \"${SUBDIR}\""
      return 1
    fi
  fi

  DISPLAY_NAME="$1"

  BUILDDIR="${CROSSER_BUILDDIR}/$1"
  if ! mkdir -p "${BUILDDIR}"
  then
    log_error "Failed to create directory ${BUILDDIR}"
    return 1
  fi
  SRCDIR="${CROSSER_SRCDIR}/${SUBDIR}"

  (
  cd "${BUILDDIR}"

  if test "$4" = "native" ; then
    export PKG_CONFIG_PATH="${NATIVE_PKG_CONFIG_PATH}"
  else
    # The argument that can be given properly via the cross-file,
    # are given that way. Here are the rest.
    export CPPFLAGS="-I${DLLSPREFIX}/include -I${TGT_HEADERS} ${CROSSER_WINVER_FLAG}"
    export LDFLAGS="-L${DLLSPREFIX}/lib"
    export PKG_CONFIG_PATH="${DLLSPREFIX}/lib/${CROSSER_PKG_ARCH}/pkgconfig"
  fi

  log_write 1 "Running meson for ${DISPLAY_NAME}"
  log_write 3 "  PKG_CONFIG_PATH: \"${PKG_CONFIG_PATH}\""
  log_write 3 "  Options: $3"

  if test "$4" = "native"
  then
    if ! meson.py setup "${SRCDIR}" . --prefix="${NATIVE_PREFIX}" $3 \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
    then
      log_error "Meson for ${DISPLAY_NAME} failed"
      return 1
    fi
  elif ! meson.py setup "${SRCDIR}" . --cross-file "${DLLSPREFIX}/etc/meson_cross_file.txt" \
       "--prefix=${DLLSPREFIX}" $3 \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
  then
    log_error "Meson for ${DISPLAY_NAME} failed"
    return 1
  fi

  log_write 1 "Running ninja for ${DISPLAY_NAME}"

  if ! ninja install \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
  then
    log_error "Ninja for ${DISPLAY_NAME} failed"
    return 1
  fi
  )

  RET=$?

  if test $RET = 0 ; then
    echo "${DISPLAY_NAME} : ${BVER}" >> "${DLLSPREFIX}/ComponentVersions.txt"
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

  if test "${SUBDIR}" = ""
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  BUILDDIR="${CROSSER_BUILDDIR}/$1"
  if ! mkdir -p "${BUILDDIR}"
  then
    log_error "Failed to create directory \"${BUILDDIR}\""
    return 1
  fi
  SRCDIR="${CROSSER_SRCDIR}/${SUBDIR}"

  (
  export CC="${CROSSER_TARGET}-gcc${TARGET_SUFFIX} -static-libgcc"
  export RANLIB="${CROSSER_TARGET}-ranlib"
  export AR="${CROSSER_TARGET}-ar"

  if ! cd "${BUILDDIR}"
  then
    log_error "Cannot change to directory \"${BUILDDIR}\""
    return 1
  fi

  export CPPFLAGS="-isystem ${DLLSPREFIX}/include -isystem ${TGT_HEADERS} ${CROSSER_WINVER_FLAG}"
  export LDFLAGS="-L${DLLSPREFIX}/lib"

  CONFOPTIONS="--prefix=${DLLSPREFIX} --shared $3"

  log_write 1 "Configuring $1"
  log_write 3 "  Options: \"${CONFOPTIONS}\""
  log_flags

  if ! "${SRCDIR}/configure" ${CONFOPTIONS} \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
  then
    log_error "Configure for $1 failed"
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default] install"
  log_write 4 "  Options: \"${CROSSER_COREOPTIONS}\""

  if ! make ${CROSSER_COREOPTIONS} \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! make ${CROSSER_COREOPTIONS} install \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
  then
    log_error "Install for $1 failed"
    return 1
  fi

  if ! cp "${DLLSPREFIX}/lib/libz.dll"* "${DLLSPREFIX}/bin/"
  then
    log_error "Failed to move libz dll:s to correct directory"
    return 1
  fi
  )

  RET=$?

  if test "${RET}" = 0 ; then
    echo "$1 : $2" >> "${DLLSPREFIX}/ComponentVersions.txt"
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
  if test "$2" = "0"
  then
    return 0
  fi

  log_packet "$1"

  SUBDIR="$(src_subdir "$1" "$2")"

  if test "${SUBDIR}" = ""
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  if is_minimum_version "${VERSION_PDCURSES}" 3.6
  then
    SUBDIR="${SUBDIR}/wincon"
    MKFILE=Makefile
  else
    SUBDIR="${SUBDIR}/win32"
    MKFILE=mingwin32.mak
  fi

  (
  if ! cd "${CROSSER_SRCDIR}/${SUBDIR}"
  then
    log_error "Cannot change to directory \"${CROSSER_SRCDIR}/${SUBDIR}\""
    return 1
  fi

  log_write 1 "Building $1"
  log_write 3 "  Make targets: [default]"
  log_write 4 "  Options: \"${CROSSER_COREOPTIONS}\""

  if ! make -f "${MKFILE}" ${CROSSER_COREOPTIONS} \
       >> "${CROSSER_LOGDIR}/stdout.log" 2>> "${CROSSER_LOGDIR}/stderr.log"
  then
    log_error "Make for $1 failed"
    return 1
  fi

  if ! cp pdcurses.a "${DLLSPREFIX}/lib/libpdcurses.a"
  then
    log_error "pdcurses.a copy failed"
    return 1
  fi
  )

  RET=$?

  if test "${RET}" = 0 ; then
    echo "$1 : $2" >> "${DLLSPREFIX}/ComponentVersions.txt"
  fi

  return $RET
}

#######################################################################################################
#
# Main
#

cd "$(dirname "$0")" || exit 1

CROSSER_BUILD_ARCH="$("${CROSSER_MAINDIR}/scripts/aux/config.guess")"
CROSSER_PKG_ARCH="$(echo ${CROSSER_BUILD_ARCH} | sed 's/-pc//')"

if ! test -e "${CROSSER_MAINDIR}/setups/${CROSSER_SETUP}.conf" ; then
  log_error "Can't find setup \"${CROSSER_SETUP}.conf\""
  exit 1
fi
. "${CROSSER_MAINDIR}/setups/${CROSSER_SETUP}.conf"

if test "${TARGET_VENDOR}" = ""
then
  export CROSSER_TARGET="${TARGET_ARCH}-${TARGET_OS}"
else
  export CROSSER_TARGET="${TARGET_ARCH}-${TARGET_VENDOR}-${TARGET_OS}"
fi

if test -d "/usr/${CROSSER_TARGET}/include"
then
  export TGT_HEADERS="/usr/${CROSSER_TARGET}/include"
fi

export DLLSPREFIX=$(setup_prefix_default "${HOME}/.crosser/<VERSION>/<VERSIONSET>/<SETUP>/winstack" "${DLLSPREFIX}")
export NATIVE_PREFIX=$(setup_prefix_default "${HOME}/.crosser/<VERSION>/<VERSIONSET>/dllshost" \
                                            "${CROSSER_HOST_PREFIX}")

if test "${TARGET_SUFFIX_P}" = "" ; then
  TARGET_SUFFIX_P="${TARGET_SUFFIX}"
fi

TARGET_GCC_VER=$(${CROSSER_TARGET}-gcc${TARGET_SUFFIX} -dumpversion 2>/dev/null | sed 's/-.*//')
TARGET_GXX_VER=$(${CROSSER_TARGET}-g++${TARGET_SUFFIX} -dumpversion 2>/dev/null | sed 's/-.*//')

if test "${TARGET_GCC_VER}" = "" ; then
  log_error "Target compiler ${CROSSER_TARGET}-gcc${TARGET_SUFFIX} version not found!"
  exit 1
fi
if test "${TARGET_GXX_VER}" = "" ; then
  log_error "Target compiler ${CROSSER_TARGET}-g++${TARGET_SUFFIX} version not found!"
  exit 1
fi

CROSSER_WINVER_FLAG="-D_WIN32_WINNT=${CROSSER_WINVER}"

log_write 2 "Install:    \"${DLLSPREFIX}\""
log_write 2 "Src:        \"${CROSSER_SRCDIR}\""
log_write 2 "Log:        \"${CROSSER_LOGDIR}\""
log_write 2 "Build:      \"${CROSSER_BUILDDIR}\""
log_write 2 "Setup:      \"${CROSSER_SETUP}\""
log_write 2 "Versionset: \"${CROSSER_VERSIONSET}\""
log_write 2 "cross-gcc:  ${TARGET_GCC_VER}"
log_write 2 "cross-g++:  ${TARGET_GXX_VER}"

CROSSER_STDCXX="-static-libstdc++"

remove_dir "${CROSSER_SRCDIR}" &&
remove_dir "${CROSSER_BUILDDIR}" &&
remove_dir "${DLLSPREFIX}" &&
remove_dir "${NATIVE_PREFIX}"
RDRET=$?

if test "${RDRET}" = "1" ; then
  log_error "Old directories not removed"
  exit 1
elif test "${RDRET}" != "0" ; then
  log_error "Failed to remove old directories"
  exit 1
fi

if ! mkdir -p "${CROSSER_SRCDIR}"
then
  log_error "Cannot create directory \"${CROSSER_SRCDIR}\""
  exit 1
fi

if ! mkdir -p "${CROSSER_BUILDDIR}"
then
  log_error "Cannot create directory \"${CROSSER_BUILDDIR}\""
  exit 1
fi

if ! mkdir -p "${DLLSPREFIX}/man/man1" ||
   ! mkdir -p "${DLLSPREFIX}/etc"
then
  log_error "Cannot create target directory hierarchy under \"${DLLSPREFIX}\""
  exit 1
fi

if ! mkdir -p "${NATIVE_PREFIX}/bin"
then
  log_error "Cannot create host directory hierarchy under \"${NATIVE_PREFIX}\""
  exit 1
fi

export DIST_NATIVE_PREFIX="${DLLSPREFIX}/linux"

export PATH="${DIST_NATIVE_PREFIX}/bin:${NATIVE_PREFIX}/bin:${NATIVE_PREFIX}/meson-${VERSION_MESON}:${PATH}"

if ! packetdir_check
then
  log_error "Packetdir missing"
  exit 1
fi

log_write 1 "Creating meson cross file"

if ! (
  TARGET_GCC=$(command -v ${CROSSER_TARGET}-gcc${TARGET_SUFFIX})
  TARGET_GPP=$(command -v ${CROSSER_TARGET}-g++${TARGET_SUFFIX})
  TARGET_AR=$(command -v ${CROSSER_TARGET}-ar)
  TARGET_STRIP=$(command -v ${CROSSER_TARGET}-strip)
  TARGET_PKGCONFIG="${DIST_NATIVE_PREFIX}/bin/${CROSSER_TARGET}-pkg-config"
  TARGET_WINDRES=$(command -v ${CROSSER_TARGET}-windres)

  if test "${TARGET_GCC}" = ""   ||
     test "${TARGET_GPP}" = ""   ||
     test "${TARGET_AR}" = ""    ||
     test "${TARGET_STRIP}" = "" ||
     test "${TARGET_WINDRES}" = ""
  then
    log_error "Cross-tools missing"
    exit 1
  fi
  if ! sed -e "s,<TARGET_GCC>,${TARGET_GCC},g" \
           -e "s,<TARGET_GPP>,${TARGET_GPP},g" \
           -e "s,<TARGET_AR>,${TARGET_AR},g" \
           -e "s,<TARGET_STRIP>,${TARGET_STRIP},g" \
           -e "s,<TARGET_PKGCONFIG>,${TARGET_PKGCONFIG},g" \
           -e "s,<TARGET_WINDRES>,${TARGET_WINDRES},g" \
           -e "s,<DLLSTACK>,${DLLSPREFIX},g" \
           "${CROSSER_MAINDIR}/scripts/${MESON_CROSS_FILE}" \
           > "${DLLSPREFIX}/etc/meson_cross_file.txt"
  then
    log_error "Meson cross-file creation failed"
    exit 1
  fi
)
then
  exit 1
fi

log_write 1 "Creating cmake toolchain file"

if ! (
  TARGET_GCC=$(command -v ${CROSSER_TARGET}-gcc${TARGET_SUFFIX})
  TARGET_GPP=$(command -v ${CROSSER_TARGET}-g++${TARGET_SUFFIX})

  if test "${TARGET_GCC}" = ""   ||
     test "${TARGET_GPP}" = ""
  then
    log_error "Cross-tools missing"
    exit 1
  fi
  if ! sed -e "s,<TARGET_GCC>,${TARGET_GCC},g" \
           -e "s,<TARGET_GPP>,${TARGET_GPP},g" \
           -e "s,<DLLSPREFIX>,${DLLSPREFIX},g" \
           "${CROSSER_MAINDIR}/scripts/${CMAKE_PLATFORM_FILE}" \
           > "${DLLSPREFIX}/etc/toolchain.cmake"
  then
    log_error "CMake toolchain file creation failed"
    exit 1
  fi
)
then
  exit 1
fi

log_write 1 "Setting up fixed environment"

if ! mkdir -p "${DLLSPREFIX}/lib/${CROSSER_PKG_ARCH}" ||
   ! ln -s ../pkgconfig "${DLLSPREFIX}/lib/${CROSSER_PKG_ARCH}/" ||
   ! mkdir -p "${NATIVE_PREFIX}/lib/${CROSSER_PKG_ARCH}" ||
   ! ln -s ../pkgconfig "${NATIVE_PREFIX}/lib/${CROSSER_PKG_ARCH}/"
then
  log_error "Failed to set up fixed environment"
  exit 1
fi

if test "${CROSSER_DOWNLOAD}" = "yes"
then
  steplist="win"
  if test "${CROSSER_SDL2}" = "yes" ; then
    steplist="${steplist},sdl2"
  fi
  if test "${CROSSER_SFML}" = "yes" ; then
    steplist="${steplist},sfml"
  fi
  if test "${CROSSER_FULL}" = "yes" ; then
    steplist="${steplist},full"
  fi
  if ! (cd "${CROSSER_PACKETDIR}" &&
        "${CROSSER_MAINDIR}/scripts/download_packets.sh" "$steplist" "${CROSSER_VERSIONSET}" "${CROSSER_SETUP}")
  then
    log_error "Downloading packets failed"
    exit 1
  fi
fi

GETTEXT_VARS="$(read_configure_vars gettext)"
CAIRO_VARS="$(read_configure_vars cairo)"
ICU_FILEVER="$(icu_filever $VERSION_ICU)"

export LD_LIBRARY_PATH="${DIST_NATIVE_PREFIX}/lib:${DIST_NATIVE_PREFIX}/lib64:${NATIVE_PREFIX}/lib:${NATIVE_PREFIX}/lib64:${NATIVE_PREFIX}/lib/${CROSSER_PKG_ARCH}"
export NATIVE_PKG_CONFIG_PATH="${DIST_NATIVE_PREFIX}/lib64/pkgconfig:${NATIVE_PREFIX}/lib/pkgconfig:${NATIVE_PREFIX}/lib64/pkgconfig"

if ! unpack_component     meson "" "meson/${VERSION_MESON}"              ||
   ! cp -R "${CROSSER_SRCDIR}/meson-${VERSION_MESON}" "${NATIVE_PREFIX}" ||
   ! unpack_component     autoconf                          ||
   ! build_component_host autoconf                          ||
   ! deldir_component     autoconf   "${VERSION_AUTOCONF}" "native-autoconf" ||
   ! unpack_component     automake                          ||
   ! build_component_host automake                          ||
   ! deldir_component     automake   $VERSION_AUTOMAKE "native-automake" ||
   ! unpack_component     libtool                           ||
   ! build_component_full native-libtool libtool            \
     "" "native" "" "" "$VERSION_LIBTOOL"                   ||
   ! deldir_build         "native-libtool"                               ||
   ! unpack_component     libffi                            ||
   ! build_component_host libffi                            ||
   ! deldir_build         "native-libffi"                   ||
   ! unpack_component     pkgconf                                            ||
   ! autogen_component    pkgconf "${VERSION_PKGCONF}"                       ||
   ! build_component_host pkgconf                                            \
     "--with-pkg-config-dir=${NATIVE_PREFIX}/lib/pkgconfig --disable-shared" ||
   ! deldir_build         "native-pkgconf"                                   ||
   ! unpack_component     pkg-config                                         ||
   ! build_component_host pkg-config                                         \
     "--with-pc-path=${NATIVE_PREFIX}/lib/pkgconfig --with-internal-glib --disable-compile-warnings" ||
   ! deldir_build         "native-pkg-config"                                ||
   ! unpack_component     pcre2                                             ||
   ! build_component_host pcre2                                             \
     "--enable-unicode-properties"                                          ||
   ! deldir_build         "native-pcre2"                                    ||
   ! unpack_component     glib                                              ||
   ! build_with_meson_host glib "-D libmount=disabled -D selinux=disabled"  ||
   ! deldir_build         "native-glib"                                     ||
   ! unpack_component     gtk-doc                                           ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_pc"                         ||
   ! patch_src gtk-doc $VERSION_GTK_DOC "gtkdoc_configheaders"              ||
   ! ( is_minimum_version "$VERSION_GTK_DOC" 1.33 ||
       ( autogen_component    gtk-doc "$VERSION_GTK_DOC" &&
         build_component_host gtk-doc ) )                                   ||
   ! ( is_smaller_version "$VERSION_GTK_DOC" 1.33 ||
       build_with_meson_host gtk-doc )                                      ||
   ! deldir_component  gtk-doc   "$VERSION_GTK_DOC"                         \
     "native-gtk-doc"                                                       ||
   ! unpack_component     gobject-introspection                             ||
   ! build_with_meson_host gobject-introspection                            ||
   ! deldir_component  gobject-introspection   $VERSION_GOBJ_INTRO            \
     "native-gobject-introspection"                                         ||
   ! build_component_host pkgconf                                                  \
     "--with-pkg-config-dir=${DLLSPREFIX}/lib/pkgconfig --disable-shared"          \
     "pkg-config"                                                                  ||
   ! deldir_component     pkgconf "${VERSION_PKGCONF}" "cross-pkgconf"             ||
   ! build_component_host pkg-config                                               \
     "--with-pc-path=${DLLSPREFIX}/lib/pkgconfig --disable-host-tool" "pkg-config" ||
   ! deldir_component     pkg-config "${VERSION_PKG_CONFIG}" "cross-pkg-config"    ||
   ! mv "${NATIVE_PREFIX}/bin/pkg-config" "${NATIVE_PREFIX}/bin/pkg-config.real"   ||
   ! ln -s "${CROSSER_PKGCONF}" "${NATIVE_PREFIX}/bin/pkg-config"                  ||
   ! mv "${DIST_NATIVE_PREFIX}/bin/${CROSSER_TARGET}-pkg-config"                   \
        "${DIST_NATIVE_PREFIX}/bin/${CROSSER_TARGET}-pkg-config.real"              ||
   ! ln -s "${CROSSER_TARGET}-${CROSSER_PKGCONF}"                                  \
        "${DIST_NATIVE_PREFIX}/bin/${CROSSER_TARGET}-pkg-config"                   ||
   ! unpack_component  icon-naming-utils                                    ||
   ! patch_src icon-naming-utils $VERSION_ICON_NUTILS "icon-nutils-pc"      ||
   ! build_component_host icon-naming-utils                                 ||
   ! deldir_component  icon-naming-utils $VERSION_ICON_NUTILS               \
     "native-icon-naming-utils"                                             ||
   ! unpack_component  icu4c         "" "icu4c-$ICU_FILEVER-src"            ||
   ! patch_src icu $VERSION_ICU icu_dbl_mant                                ||
   ! (is_smaller_version $VERSION_ICU 59.1 ||
      patch_src icu $VERSION_ICU icu_filetools_inc )                        ||
   ! CXX="g++" CFLAGS="-fPIC" build_component_full native-icu4c icu4c ""    \
     "native" "icu/source" "" "" "yes"                                      ||
   ! unpack_component tiff                                                  ||
   ! build_component_host tiff                                              ||
   ! deldir_build         "native-tiff"                                     ||
   ! unpack_component     libxml2                                           ||
   ! build_component_host libxml2 "--without-python"                        ||
   ! deldir_build         "native-libxml2"                                  ||
   ! unpack_component  shared-mime-info                                     ||
   ! ln -s "../lib/pkgconfig" "${NATIVE_PREFIX}/share/pkgconfig"            ||
   ! ( is_minimum_version "${VERSION_SHARED_MIME_INFO}" 2.2 ||
       patch_src shared-mime-info "${VERSION_SHARED_MIME_INFO}" \
                 "smi-meson-0.60" )                                         ||
   ! ( is_smaller_version "${VERSION_SHARED_MIME_INFO}" 2.2 ||
       patch_src shared-mime-info "${VERSION_SHARED_MIME_INFO}" "smi-html" ) ||
   ! (is_smaller_version "${VERSION_SHARED_MIME_INFO}" 2.0 ||
      XML_CATALOG_FILES="/etc/xml/catalog" \
      build_with_meson_host shared-mime-info )                              ||
   ! (is_minimum_version "${VERSION_SHARED_MIME_INFO}" 2.0 ||
      build_component_full native-shared-mime-info shared-mime-info \
      "" "native" "" "no" )                                                 ||
   ! deldir_build         "native-shared-mime-info"                         ||
   ! unpack_component     util-macros                                       ||
   ! build_component_host util-macros                                       ||
   ! deldir_component     util-macros $VERSION_UTIL_MACROS                  \
     "native-util-macros"                                                   ||
   ! unpack_component     libpng                                            ||
   ! patch_src            libpng      "${VERSION_PNG}" "png_epsilon-1.6.8"  ||
   ! build_component_host libpng                                            ||
   ! deldir_build         "native-libpng"                                   ||
   ! unpack_component     ImageMagick ""                                    \
     "ImageMagick/${VERSION_IMAGEMAGICK}"                                   ||
   ! ( is_minimum_version "${VERSION_IMAGEMAGICK}" 7.0.10 ||
       patch_src ImageMagick "${VERSION_IMAGEMAGICK}" "im_pthread" )        ||
   ! ( is_smaller_version "${VERSION_IMAGEMAGICK}" 7.0.10 ||
       patch_src ImageMagick "${VERSION_IMAGEMAGICK}" "im_pthread-7.0.10" ) ||
   ! patch_src ImageMagick "${VERSION_IMAGEMAGICK}" "im_nonnativewin"       ||
   ! build_component_host ImageMagick "--without-utilities"                 ||
   ! deldir_build         "native-ImageMagick"
then
  log_error "Native build failed"
  exit 1
fi

SQL_VERSTR="$(sqlite_verstr ${VERSION_SQLITE})"
READLINE_VARS="$(read_configure_vars readline)"

if ! build_component_full libtool libtool "" "" "" ""                 \
     "${VERSION_LIBTOOL}"                                             ||
   ! deldir_component  libtool    $VERSION_LIBTOOL "libtool"          ||
   ! unpack_component  libiconv                                       ||
   ! build_component   libiconv                                       ||
   ! deldir_component  libiconv   $VERSION_ICONV "libiconv"           ||
   ! unpack_component  zlib                                           ||
   ! patch_src zlib $VERSION_ZLIB zlib_seeko-1.2.6-2                  ||
   ! patch_src zlib $VERSION_ZLIB zlib_nolibc-1.2.6-2                 ||
   ! patch_src zlib $VERSION_ZLIB zlib_dllext                         ||
   ! (is_smaller_version $VERSION_ZLIB 1.2.12 ||
      patch_src zlib $VERSION_ZLIB zlib_cc )                          ||
   ! build_zlib        zlib       $VERSION_ZLIB                       ||
   ! deldir_component  zlib       $VERSION_ZLIB "zlib"                ||
   ! unpack_component  xz                                             ||
   ! (is_minimum_version "${VERSION_XZ}" 5.2.6 ||
      patch_src xz      "${VERSION_XZ}" "xzgrep-ZDI-CAN-16587" )      ||
   ! build_component_full xz xz   "--disable-threads" "windres"       ||
   ! deldir_component  xz         "${VERSION_XZ}" "xz"                ||
   ! unpack_component  zstd                                           ||
   ! build_with_meson_full zstd zstd "" "" "build/meson"              ||
   ! deldir_component  zstd       $VERSION_ZSTD "zstd"                ||
   ! unpack_component  curl                                           ||
   ! (is_minimum_version "${VERSION_CURL}" 7.86.0 ||
      patch_src curl "${VERSION_CURL}" curl_winpollfd )               ||
   ! build_component_full curl curl                                   \
     "--disable-pthreads --with-schannel" "nounicode"                 ||
   ! deldir_component  curl       "${VERSION_CURL}" "curl"            ||
   ! unpack_component  sqlite                                                        \
     "" "sqlite-autoconf-${SQL_VERSTR}"                                              ||
   ! build_component_full sqlite sqlite                                              \
     "--disable-threadsafe" "nounicode" "sqlite-autoconf-${SQL_VERSTR}"              ||
   ! deldir_component  sqlite-autoconf "${SQL_VERSTR}" "sqlite"                      ||
   ! ( test "$CROSSER_POSIX" = "yes" || test "${VERSION_TCT}" = "0" ||
      ( unpack_component  tinycthread "" "tinycthread/v${VERSION_TCT}"  &&
        cp ${CROSSER_MAINDIR}/patch/tct/Makefile.am                     \
           ${CROSSER_SRCDIR}/tinycthread-${VERSION_TCT}/source/         &&
        cp ${CROSSER_MAINDIR}/patch/tct/configure.ac                    \
           ${CROSSER_SRCDIR}/tinycthread-${VERSION_TCT}/source/         &&
        ( cd ${CROSSER_SRCDIR}/tinycthread-${VERSION_TCT}/source &&
          aclocal && autoconf && automake --add-missing --foreign )     \
             >>$CROSSER_LOGDIR/stdout.log 2>>$CROSSER_LOGDIR/stderr.log &&
        build_component_full tinycthread tinycthread "" ""              \
          "tinycthread-${VERSION_TCT}/source"                           &&
        deldir_component  tinycthread $VERSION_TCT "tinycthread" ))                  ||
   ! (test "$CROSSER_POSIX" = "yes" ||
      is_smaller_version $VERSION_ICU 64.1 ||
      patch_src icu $VERSION_ICU icu_tct )                                           ||
   ! TARGET_SUFFIX="${TARGET_SUFFIX_P}" build_component_full icu4c icu4c                                                \
     "--with-cross-build=$CROSSER_BUILDDIR/native-icu4c" "" "icu/source" "" "" "yes" ||
   ! deldir_build      "native-icu4c"                                                ||
   ! deldir_component  icu        $VERSION_ICU "icu4c"                               ||
   ! patch_src ImageMagick "${VERSION_IMAGEMAGICK}" "im_link_ws2_7"                  ||
   ! patch_src ImageMagick "${VERSION_IMAGEMAGICK}" "im_dll_not"                     ||
   ! build_component   ImageMagick                                                   \
     "--without-bzlib --without-threads --without-magick-plus-plus --disable-openmp --without-utilities" ||
   ! deldir_component  ImageMagick "${VERSION_IMAGEMAGICK}" "ImageMagick"            ||
   ! build_component   libpng                                                        ||
   ! deldir_component  libpng     "${VERSION_PNG}" "libpng"                          ||
   ! unpack_component  gettext                                                       ||
   ! (is_smaller_version $VERSION_GETTEXT 0.20 ||
      is_minimum_version $VERSION_GETTEXT 0.20.2 ||
      patch_src gettext $VERSION_GETTEXT "gettext_pthread_test_disable" )            ||
   ! (is_smaller_version "$VERSION_GETTEXT" 0.21   ||
      is_minimum_version "$VERSION_GETTEXT" 0.21.1 ||
      patch_src gettext $VERSION_GETTEXT "gettext_fs_ruby" )                         ||
   ! LIBS="-liconv" build_component gettext                                          \
     "$GETTEXT_VARS --enable-relocatable --enable-threads=windows --disable-libasprintf --without-emacs"    ||
   ! deldir_component  gettext    $VERSION_GETTEXT "gettext"                         ||
   ! build_component   pcre2                                          \
     "--disable-cpp --enable-unicode-properties --enable-pcre2-16"    ||
   ! deldir_component  pcre2      $VERSION_PCRE2    "pcre2"           ||
   ! build_component   libffi                                         ||
   ! deldir_component  libffi     $VERSION_FFI     "libffi"           ||
   ! build_with_meson  glib                                           ||
   ! deldir_component  glib       "${VERSION_GLIB}" "glib"            ||
   ! unpack_component  fribidi                                        ||
   ! build_component   fribidi    "--disable-docs"                    ||
   ! deldir_component  fribidi    $VERSION_FRIBIDI "fribidi"
then
  log_error "Build failed"
  exit 1
fi

if test "${CROSSER_READLINE}" = "yes" ; then
if ! unpack_component  PDCurses                                          ||
   ! (is_minimum_version $VERSION_PDCURSES 3.6 ||
      patch_src PDCurses $VERSION_PDCURSES "PDCurses_crosswin" )         ||
   ! (is_smaller_version $VERSION_PDCURSES 3.6 ||
      patch_src PDCurses $VERSION_PDCURSES "PDCurses_crosswin-3.6" )     ||
   ! build_pdcurses    PDCurses $VERSION_PDCURSES                        \
     "--without-x"                                                       ||
   ! deldir_src        PDCurses $VERSION_PDCURSES                        ||
   ! unpack_component  ncurses                                           ||
   ! patch_src ncurses $VERSION_NCURSES "ncurses_windows_h"              ||
   ! patch_src ncurses $VERSION_NCURSES "ncurses_static"                 ||
   ! build_component   ncurses "--enable-term-driver"                    ||
   ! deldir_component  ncurses $VERSION_NCURSES "ncurses"                ||
   ! unpack_component  readline                                          ||
   ! patch_readline                                                      ||
   ! patch_src readline $VERSION_READLINE "readline_posix"               ||
   ! (is_minimum_version $VERSION_READLINE 7.0 ||
      patch_src readline $VERSION_READLINE "readline_sighup" )           ||
   ! (is_smaller_version $VERSION_READLINE 7.0 ||
      is_minimum_version $VERSION_READLINE 8.0 ||
      patch_src readline $VERSION_READLINE "readline_chown" )            ||
   ! patch_src readline $VERSION_READLINE "readline_statf"               ||
   ! patch_src readline $VERSION_READLINE "readline_ncurses"             ||
   ! build_component   readline                                          \
     "$READLINE_VARS --with-curses"                                      ||
   ! deldir_component  readline   $VERSION_READLINE "readline"
then
  log_error "Readline build failed"
  exit 1
fi
fi

if ! unpack_component jpeg  "" "jpegsrc.v${VERSION_JPEG}"             ||
   ! build_component jpeg "--enable-shared"                           ||
   ! deldir_component jpeg $VERSION_JPEG "jpeg"
then
  log_error "Libjpeg build failed"
  exit 1
fi

if test "${VERSION_PANGO2}" != "0"
then
  HB_EXTRA_CONFIG="-Ddirectwrite=enabled"
else
  HB_EXTRA_CONFIG=""
fi

if ! build_component   tiff                                                 ||
   ! deldir_component  tiff       "${VERSION_TIFF}" "tiff"                  ||
   ! build_component   libxml2                                              \
     "--without-python --with-zlib=${DLLSPREFIX} --with-lzma=${DLLSPREFIX}" ||
   ! deldir_component  libxml2    "${VERSION_XML2}" "libxml2"               ||
   ! (is_smaller_version "${VERSION_SHARED_MIME_INFO}" 2.0 ||
      XML_CATALOG_FILES="/etc/xml/catalog" \
      build_with_meson shared-mime-info )                                   ||
   ! (is_minimum_version "${VERSION_SHARED_MIME_INFO}" 2.0 ||
      build_component_full shared-mime-info shared-mime-info "" "" "" \
       "no" )                                                                ||
   ! deldir_component  shared-mime-info "${VERSION_SHARED_MIME_INFO}"        \
     "shared-mime-info"                                                      ||
   ! unpack_component  jansson                                               ||
   ! build_component   jansson                                               ||
   ! deldir_component  jansson    "${VERSION_JANSSON}" "jansson"             ||
   ! unpack_component  freetype                                              ||
   ! build_component   freetype   "--without-bzip2"                          ||
   ! deldir_component  freetype   "${VERSION_FREETYPE}" "freetype"           ||
   ! unpack_component  harfbuzz "" "harfbuzz/${VERSION_HARFBUZZ}"            ||
   ! ( is_max_version "${VERSION_HARFBUZZ}" 2.5.0 ||
       patch_src harfbuzz "${VERSION_HARFBUZZ}" "harfbuzz_pthread_disable" ) ||
   ! ( is_minimum_version "${VERSION_HARFBUZZ}" 2.6.7 ||
       patch_src       harfbuzz   "${VERSION_HARFBUZZ}" "harfbuzz_python3" ) ||
   ! build_with_meson  harfbuzz \
       "-Dicu=disabled -Dtests=disabled -Ddocs=disabled ${HB_EXTRA_CONFIG}"  ||
   ! deldir_component  harfbuzz   "${VERSION_HARFBUZZ}" "harfbuzz"           ||
   ! unpack_component  fontconfig                                            ||
   ! ( is_smaller_version $VERSION_FONTCONFIG 2.12.3 ||
       patch_src       fontconfig $VERSION_FONTCONFIG fontconfig_fcobjs_prototypes ) ||
   ! ( is_smaller_version $VERSION_FONTCONFIG 2.13.0 ||
       is_minimum_version $VERSION_FONTCONFIG 2.13.90 ||
       patch_src       fontconfig $VERSION_FONTCONFIG fontconfig_disable_test) ||
   ! ( is_smaller_version $VERSION_FONTCONFIG 2.13.90 ||
       patch_src       fontconfig $VERSION_FONTCONFIG fontconfig_disable_test-2.13.96) ||
   ! build_component   fontconfig                                           \
     "--with-freetype-config=${DLLSPREFIX}/bin/freetype-config --with-arch=${CROSSER_TARGET} --enable-libxml2" ||
   ! deldir_component  fontconfig $VERSION_FONTCONFIG "fontconfig"          ||
   ! unpack_component  libepoxy                                             ||
   ! ( is_minimum_version $VERSION_LIBEPOXY 1.5.0 ||
       build_component   libepoxy )                                         ||
   ! ( is_smaller_version $VERSION_LIBEPOXY 1.5.0 ||
       build_with_meson   libepoxy )                                        ||
   ! deldir_component  libepoxy $VERSION_LIBEPOXY "libepoxy"                ||
   ! unpack_component  pixman                                               ||
   ! patch_src          pixman $VERSION_PIXMAN pixman_epsilon               ||
   ! build_component   pixman                                               \
     "--disable-gtk"                                                        ||
   ! deldir_component  pixman     $VERSION_PIXMAN "pixman"                  ||
   ! unpack_component  cairo                                                   ||
   ! rm -f "${CROSSER_SRCDIR}/cairo-${VERSION_CAIRO}/src/cairo-features.h"     ||
   ! ( is_minimum_version    "${VERSION_CAIRO}" 1.17.8 ||
       patch_src       cairo "${VERSION_CAIRO}" "cairo-1.12.10_epsilon" )      ||
   ! ( is_minimum_version    "${VERSION_CAIRO}" 1.17.8 ||
       patch_src       cairo "${VERSION_CAIRO}" "cairo_fortify_disable" )      ||
   ! ( is_minimum_version    "${VERSION_CAIRO}" 1.15.2 ||
       patch_src       cairo "${VERSION_CAIRO}" cairo_1.14.2+ )                ||
   ! ( is_smaller_version    "${VERSION_CAIRO}" 1.17.6 ||
       ( patch_src     cairo "${VERSION_CAIRO}" "cairo_missing_unused" &&
         patch_src     cairo "${VERSION_CAIRO}" "cairo_missing_win32dwrite" &&
         patch_src     cairo "${VERSION_CAIRO}" "cairo_missing_perf" ))        ||
   ! ( is_minimum_version "${VERSION_CAIRO}" 1.17.6 ||
       build_component   cairo "${CAIRO_VARS} --disable-xlib --enable-win32" ) ||
   ! ( is_smaller_version "${VERSION_CAIRO}" 1.17.6 ||
       build_with_meson cairo "-Dxlib=disabled" )                              ||
   ! deldir_component  cairo      "${VERSION_CAIRO}" "cairo"                   ||
   ! unpack_component  pango                                                ||
   ! (is_smaller_version $VERSION_PANGO 1.44 ||
      is_minimum_version $VERSION_PANGO 1.48 ||
      build_with_meson pango "-Dintrospection=false" )                      ||
   ! (is_smaller_version $VERSION_PANGO 1.48 ||
      build_with_meson pango "-Dintrospection=disabled" )                   ||
   ! deldir_component  pango      $VERSION_PANGO "pango"                    ||
   ! unpack_component  pango2                                               ||
   ! patch_src         pango2 "${VERSION_PANGO2}" "pango2_cairoless_extst"  ||
   ! build_with_meson  pango2 "-Dintrospection=disabled -Dcairo=disabled"   ||
   ! deldir_component  pango2    "${VERSION_PANGO2}" "pango2"               ||
   ! unpack_component  atk                                                  ||
   ! (is_minimum_version $VERSION_ATK 2.29.1 ||
      build_component   atk )                                               ||
   ! (is_smaller_version $VERSION_ATK 2.29.1 ||
      build_with_meson atk "-D introspection=false" )                       ||
   ! deldir_component  atk        $VERSION_ATK "atk"
then
  log_error "Build failed"
  exit 1
fi

if test "${CROSSER_GTK3}" = "no" && test "${CROSSER_GTK4}" != "yes"
then
  CROSSER_GTK=no
fi

if test "${CROSSER_GTK}" != "no" ; then
if ! unpack_component     gdk-pixbuf                                  ||
   ! (is_smaller_version "$VERSION_GDK_PIXBUF" 2.42.9 ||
      build_with_meson gdk-pixbuf \
        "-Drelocatable=true -Dintrospection=disabled -Dman=false" )   ||
   ! (is_smaller_version "$VERSION_GDK_PIXBUF" 2.42.0 ||
      is_minimum_version "$VERSION_GDK_PIXBUF" 2.42.9 ||
      build_with_meson gdk-pixbuf \
        "-D relocatable=true -D introspection=disabled" ) ||
   ! (is_minimum_version "$VERSION_GDK_PIXBUF" 2.42.0 ||
      build_with_meson gdk-pixbuf \
        "-D relocatable=true -D x11=false -D gir=false" )             ||
   ! deldir_component gdk-pixbuf $VERSION_GDK_PIXBUF "gdk-pixbuf"
then
  log_error "gtk+ stack build failed"
  exit 1
fi

# This is within CROSSER_GTK != xno
if test "${CROSSER_GTK3}" != "no" ; then
if ! unpack_component gtk3                                            ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gdk/gdkconfig.h         ||
   ! rm -f $CROSSER_SRCDIR/gtk+-$VERSION_GTK3/gtk/gtk.gresource.xml   ||
   ! patch_src gtk+ $VERSION_GTK3 "gtk3_wm_macros-3.24.14"            ||
   ! ( is_minimum_version $VERSION_GTK3 3.24.32 ||
       patch_src gtk+ $VERSION_GTK3 "gtk3_host_no_install-3.24.16" )  ||
   ! ( is_smaller_version "$VERSION_GTK3" 3.24.20 ||
       is_minimum_version "$VERSION_GTK3" 3.24.36 ||
       patch_src gtk+ "$VERSION_GTK3" "gtk3_ver_test_disable" )       ||
   ! build_with_meson gtk3                                            \
     "-Dx11_backend=false -Dwayland_backend=false -Dwin32_backend=true -Dintrospection=false"                                                    ||
   ! deldir_component gtk+        $VERSION_GTK3 "gtk3"
then
  log_error "gtk+-3 build failed"
  exit 1
fi
fi

# This is within CROSSER_GTK != xno
if ! unpack_component libcroco                                        ||
   ! build_component  libcroco                                        ||
   ! deldir_component libcroco    $VERSION_CROCO   "libcroco"         ||
   ! unpack_component hicolor-icon-theme                              ||
   ! build_component  hicolor-icon-theme                              ||
   ! deldir_component hicolor-icon-theme $VERSION_HICOLOR             \
     "hicolor-icon-theme"                                             ||
   ! unpack_component tango-icon-theme                                ||
   ! patch_src tango-icon-theme "${VERSION_TANGO_ICONS}"              \
     "tango_pkg_config_host"                                          ||
   ! PKG_CONFIG_FOR_BUILD="$(host_pkg_config)"                        \
     PKG_PATH_FOR_BUILD="${NATIVE_PKG_CONFIG_PATH}"                   \
     build_component  tango-icon-theme   "${VERSION_TANGO_ICONS}"     ||
   ! deldir_component tango-icon-theme   "${VERSION_TANGO_ICONS}"     \
     "tango-icon-theme"                                               ||
   ! unpack_component adwaita-icon-theme                              ||
   ! (is_minimum_version "${VERSION_ADWAITA_ICON}" 45.0 ||
      (patch_src adwaita-icon-theme "${VERSION_ADWAITA_ICON}" \
         "adwaita_no_host_icon_cache" &&
       autogen_component adwaita-icon-theme "${VERSION_ADWAITA_ICON}" \
         "aclocal automake" &&
       build_component  adwaita-icon-theme ) )                        ||
    ! (is_smaller_version "${VERSION_ADWAITA_ICON}" 45.0 ||
       build_with_meson adwaita-icon-theme )                          ||
   ! deldir_component adwaita-icon-theme "${VERSION_ADWAITA_ICON}"    \
     "adwaita-icon-theme"
then
  log_error "gtk+ theme stack build failed"
  exit 1
fi
fi

if test "${CROSSER_GTK}" != "no" && test "${CROSSER_GTK4}" = "yes" ; then
if ! unpack_component  graphene                                         ||
   ! ( is_minimum_version $VERSION_GRAPHENE 1.10.0 ||
       patch_src graphene $VERSION_GRAPHENE graphene_epsilon )          ||
   ! patch_src graphene $VERSION_GRAPHENE "graphene_infinity_cast"      ||
   ! patch_src graphene $VERSION_GRAPHENE "graphene_nopthread"          ||
   ! ( ( is_minimum_version $VERSION_GRAPHENE 1.10.6 &&
         build_with_meson graphene "-Dintrospection=disabled" ) ||
       ( is_smaller_version $VERSION_GRAPHENE 1.10.6 &&
         build_with_meson  graphene "-D introspection=false" ) )        ||
   ! deldir_component  graphene   $VERSION_GRAPHENE "graphene"          ||
   ! unpack_component  libxkbcommon                                     ||
   ! (is_minimum_version "${VERSION_XKBCOMMON}" 1.1.0 ||
      patch_src libxkbcommon "${VERSION_XKBCOMMON}" "xkbcommon_test_opt" ) ||
   ! (is_smaller_version "${VERSION_XKBCOMMON}" 1.2.0 ||
      patch_src libxkbcommon "${VERSION_XKBCOMMON}" "xkbcommon_test_opt-1.2" ) ||
   ! (is_smaller_version "${VERSION_XKBCOMMON}" 1.0.0 ||
      is_minimum_version "${VERSION_XKBCOMMON}" 1.4.1 ||
      patch_src libxkbcommon "${VERSION_XKBCOMMON}" "xkbcommon_eof" )      ||
   ! (is_smaller_version "${VERSION_XKBCOMMON}" 1.0.0 ||
      patch_src libxkbcommon "${VERSION_XKBCOMMON}" "xkbcommon_mscver" )   ||
   ! build_with_meson  libxkbcommon                                        \
     "-Denable-x11=false -Denable-wayland=false -Denable-docs=false"       ||
   ! deldir_component  libxkbcommon  "${VERSION_XKBCOMMON}" "libxkbcommon" ||
   ! unpack_component  gtk4                                                ||
   ! (is_minimum_version "${VERSION_GTK4}" 4.9 ||
      patch_src gtk  "${VERSION_GTK4}" "gtk4_winnt" )                      ||
   ! (is_smaller_version "${VERSION_GTK4}" 4.9 ||
      patch_src gtk  "${VERSION_GTK4}" "gtk4_winnt-4.9" )                  ||
   ! patch_src gtk  "${VERSION_GTK4}" "gtk4_stdlib_inc"                    ||
   ! build_with_meson gtk4 \
     "-D x11-backend=false -D wayland-backend=false -D win32-backend=true -D introspection=disabled -D build-tests=false -D media-gstreamer=disabled"                                  ||
   ! deldir_component  gtk        "${VERSION_GTK4}" "gtk4"
then
  log_error "gtk4 chain build failed"
  exit 1
fi
fi

if ! unpack_component  libogg                                         ||
   ! build_component   libogg                                         ||
   ! deldir_component  libogg     $VERSION_OGG "libogg"               ||
   ! unpack_component  libvorbis                                      ||
   ! build_component   libvorbis                                      ||
   ! deldir_component  libvorbis  $VERSION_VORBIS "libvorbis"         ||
   ! unpack_component  flac                                           ||
   ! (is_minimum_version "${VERSION_FLAC}" 1.3.4     ||
      LIBS="-lssp" build_component flac              \
                   "--disable-cpplibs --disable-ogg" )                ||
   ! (is_smaller_version "${VERSION_FLAC}" 1.3.4     ||
      build_with_cmake  flac                         \
              "-DWITH_STACK_PROTECTOR=OFF -DWITH_OGG=OFF" )           ||
   ! deldir_component  flac   "${VERSION_FLAC}" "flac"
then
  log_error "Audio stack build failed"
  exit 1
fi

if test "${CROSSER_SDL2}" = "yes" ; then
if ! unpack_component  SDL2                                            ||
   ! patch_src SDL2 "${VERSION_SDL2}" "sdl2_epsilon"                   ||
   ! build_component_def_make SDL2                                     ||
   ! deldir_component  SDL2       "${VERSION_SDL2}" "SDL2"             ||
   ! unpack_component  SDL2_image                                      ||
   ! build_component   SDL2_image                                      ||
   ! deldir_component  SDL2_image "${VERSION_SDL2_IMAGE}" "SDL2_image" ||
   ! unpack_component  SDL2_gfx                                        ||
   ! autogen_component SDL2_gfx   "${VERSION_SDL2_GFX}" \
        "aclocal automake autoconf"                                    ||
   ! build_component   SDL2_gfx                                        ||
   ! deldir_component  SDL2_gfx   "${VERSION_SDL2_GFX}"   "SDL2_gfx"   ||
   ! unpack_component  SDL2_ttf                                        ||
   ! touch "${CROSSER_SRCDIR}/SDL2_ttf-${VERSION_SDL2_TTF}/NEWS"       ||
   ! touch "${CROSSER_SRCDIR}/SDL2_ttf-${VERSION_SDL2_TTF}/README"     ||
   ! touch "${CROSSER_SRCDIR}/SDL2_ttf-${VERSION_SDL2_TTF}/AUTHORS"    ||
   ! touch "${CROSSER_SRCDIR}/SDL2_ttf-${VERSION_SDL2_TTF}/ChangeLog"  ||
   ! autogen_component SDL2_ttf   "${VERSION_SDL2_TTF}" \
        "aclocal automake autoconf"                                    ||
   ! build_component   SDL2_ttf                                        \
     "--with-freetype-exec-prefix=${DLLSPREFIX}"                       ||
   ! deldir_component  SDL2_ttf   "${VERSION_SDL2_TTF}"   "SDL2_ttf"   ||
   ! unpack_component  SDL2_mixer                                      ||
   ! build_with_cmake  SDL2_mixer                                      \
     "-DSDL2MIXER_OPUS=OFF -DSDL2MIXER_MOD_MODPLUG=OFF -DSDL2MIXER_MIDI_FLUIDSYNTH=OFF" ||
   ! deldir_component  SDL2_mixer "${VERSION_SDL2_MIXER}" "SDL2_mixer"
then
  log_error "SDL2 stack build failed"
  exit 1
fi
fi

if test "${CROSSER_SFML}" = "yes" ; then
if ! unpack_component     ffmpeg                                                ||
   ! build_component_full ffmpeg ffmpeg                                         \
     "--prefix=${DLLSPREFIX} --cross-prefix=$CROSSER_TARGET- --target-os=win32 --arch=$TARGET_ARCH --disable-x86asm"    \
     "custom"                                                                   ||
   ! deldir_component     ffmpeg $VERSION_FFMPEG "ffmpeg"                       ||
   ! unpack_component     openal-soft                                           ||
   ! (is_minimum_version $VERSION_OPENAL 1.19.0 ||
      patch_src openal-soft $VERSION_OPENAL "oals_inc_check_param" )            ||
   ! (is_smaller_version $VERSION_OPENAL 1.19.0 ||
      is_minimum_version "$VERSION_OPENAL" 1.20.0 ||
      patch_src openal-soft $VERSION_OPENAL "oals_inc_check_param-1.19" )       ||
   ! (is_smaller_version "$VERSION_OPENAL" 1.20.0 ||
      patch_src openal-soft "$VERSION_OPENAL" "oals_WIN32_WINNT" )              ||
   ! (is_smaller_version $VERSION_OPENAL 1.19.0 ||
      is_minimum_version "$VERSION_OPENAL" 1.20.0 ||
      patch_src openal-soft $VERSION_OPENAL "oals_externs" )                    ||
   ! build_with_cmake_full openal-soft openal-soft "-DALSOFT_EXAMPLES=OFF"      \
     "custom"                                                                   ||
   ! deldir_component     openal-soft $VERSION_OPENAL "openal-soft"             ||
   ! unpack_component     sfml "" "SFML-${VERSION_SFML}-sources"                ||
   ! build_component_full sfml sfml "" "custom" "SFML-${VERSION_SFML}"          ||
   ! deldir_component     "SFML-${VERSION_SFML}" "" "sfml"
then
    log_error "SFML stack build failed"
    exit 1
fi
fi

if test "${CROSSER_QT5}" = "yes"
then
if ! unpack_component qt5                                                    ||
   ! (is_smaller_version $VERSION_QT5 5.14.0 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_g++-5.14" )               ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_disableidc-5.4.2"       ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_linkflags-5.11"         ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_vs_interop-5.11"        ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_dllsprefix-5.11"        ||
   ! (is_smaller_version $VERSION_QT5 5.14.2 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_winextras_disable-5.14.2" ) ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_yarr_inc_conflict"         ||
   ! (is_smaller_version $VERSION_QT5 5.14 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_localtime_not_r-5.14" )   ||
   ! (is_minimum_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_python3" )                ||
   ! (is_smaller_version "$VERSION_QT5" 5.15 ||
      is_minimum_version "$VERSION_QT5" 5.15.9 ||
      patch_src qt-everywhere-src "$VERSION_QT5" "qt_python3-5.15" )         ||
   ! (is_smaller_version "$VERSION_QT5" 5.15.9 ||
      patch_src qt-everywhere-src "$VERSION_QT5" "qt5_python3-5.15.9" )      ||
   ! (is_smaller_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_test_thread_disable" )    ||
   ! (is_smaller_version $VERSION_QT5 5.15 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_location_disable" )       ||
   ! (is_smaller_version $VERSION_QT5 5.14.0 ||
      patch_src qt-everywhere-src $VERSION_QT5 "qt_quick3d_req_ogl" )        ||
   ! patch_src qt-everywhere-src $VERSION_QT5 "qt_d3d12_disable"             ||
   ! (is_minimum_version "$VERSION_QT5" 5.15.5 ||
      patch_src qt-everywhere-src "$VERSION_QT5" "qt_limits_inc")            ||
   ! (is_minimum_version "$VERSION_QT5" 5.15.4 ||
      (patch_src qt-everywhere-src "$VERSION_QT5" "qt5-CVE-2022-25643-5.15" &&
       patch_src qt-everywhere-src "$VERSION_QT5" "qt5-CVE-2022-25255-qprocess5-15" &&
       patch_src qt-everywhere-src "$VERSION_QT5" "qt5-CVE-2018-25032-5.15" ) ) ||
   ! (is_minimum_version "$VERSION_QT5" 5.15.7 ||
      patch_src qt-everywhere-src "$VERSION_QT5" "qt5-CVE-2022-37434-qtbase-5.15" ) ||
   ! (is_minimum_version "$VERSION_QT5" 5.15.9 ||
      patch_src qt-everywhere-src "$VERSION_QT5" "qt5-CVE-2023-24607" )         ||
   ! (is_minimum_version "${VERSION_QT5}" 5.15.11 ||
      patch_src qt-everywhere-src "${VERSION_QT5}" "qt5-CVE-2023-34410" )       ||
   ! build_component_full  qt5 qt5                                              \
     "-opensource -confirm-license -xplatform win32-g++ -plugindir ${DLLSPREFIX}/qt5/plugins -headerdir ${DLLSPREFIX}/qt5/include -device-option CROSS_COMPILE=${CROSSER_TARGET}- -device-option DLLSPREFIX=${DLLSPREFIX} -device-option EXTRA_LIBDIR=${DLLSPREFIX}/lib -device-option EXTRA_INCDIR=${DLLSPREFIX}/include -nomake examples -no-opengl -no-evr -system-pcre -system-zlib -system-harfbuzz" \
     "qt" "" "" "" "yes"                                                        ||
   ! deldir_component qt-everywhere-src "${VERSION_QT5}" "qt5"
then
  log_error "Qt5 stack build failed"
  exit 1
fi
fi

if test "${CROSSER_QT6}" = "yes"
then

QT6_EXTRA_CONF=""
if is_minimum_version "${VERSION_QT6}" 6.4.0
then
  QT6_EXTRA_CONF+=" -skip qtmultimedia"
fi

if ! unpack_component qt6                                                       ||
   ! (is_minimum_version "${VERSION_QT6}" 6.2.4 ||
      (patch_src qt-everywhere-src "${VERSION_QT6}" "qt6-CVE-2022-25643-6.2" &&
       patch_src qt-everywhere-src "${VERSION_QT6}" "qt6-CVE-2022-25255-qprocess6-2")) ||
   ! (is_minimum_version "${VERSION_QT6}" 6.2.5 ||
      (patch_src qt-everywhere-src "${VERSION_QT6}" "qt6-CVE-2022-1096-6.2" &&
       patch_src qt-everywhere-src "${VERSION_QT6}" "qt6-CVE-2018-25032-6.2" ))      ||
   ! (is_minimum_version "${VERSION_QT6}" 6.4.0 ||
      patch_src qt-everywhere-src "${VERSION_QT6}" "qt6-check_for_ulimit" )          ||
   ! (is_minimum_version "${VERSION_QT6}" 6.4.3 ||
      patch_src qt-everywhere-src "${VERSION_QT6}" "qt6-CVE-2023-24607-6.2" )        ||
   ! build_with_cmake_full "native-qt6" "qt6"                                      \
     "-opensource -confirm-license -qt-harfbuzz -no-opengl"                        \
     "native-qt6"                                                                  ||
   ! deldir_build "native-qt6"                                                     ||
   ! build_with_cmake_full  qt6 qt6                                                \
     "-opensource -confirm-license -xplatform win32-g++ -qt-host-path ${DIST_NATIVE_PREFIX} -plugindir ${DLLSPREFIX}/qt6/plugins -headerdir ${DLLSPREFIX}/qt6/include -device-option CROSS_COMPILE=${CROSSER_TARGET}- -device-option EXTRA_LIBDIR=${DLLSPREFIX}/lib -device-option EXTRA_INCDIR=${DLLSPREFIX}/include -nomake examples -no-opengl -pkg-config -system-pcre -system-harfbuzz -skip qtquick3d -skip qtquick3dphysics -skip qtactiveqt -skip qttools -skip qtcoap -skip qtdoc -skip qtmqtt -skip qtopcua -skip qttranslations ${QT6_EXTRA_CONF} -- -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_TOOLCHAIN_FILE=${DLLSPREFIX}/etc/toolchain.cmake -DCMAKE_PREFIX_PATH=${DLLSPREFIX}" \
     "qt"                                                                          ||
   ! deldir_component qt-everywhere-src "${VERSION_QT6}" "qt6"
then
  log_error "Qt6 stack build failed"
  exit 1
fi

# Hack to fix broken .pc file produced by Qt6 build
if is_minimum_version "${VERSION_QT6}" 6.3.0
then

if ! sed 's/UNICODE>/UNICODE/' "${DLLSPREFIX}/lib/pkgconfig/Qt6Platform.pc" \
     > "${CROSSER_TMPDIR}/fixed.pc"                                         ||
   ! mv "${CROSSER_TMPDIR}/fixed.pc" "${DLLSPREFIX}/lib/pkgconfig/Qt6Platform.pc"
then
  log_error "Qt6 .pc file fixing failed"
  exit 1
fi
fi

if ! test -f "${DIST_NATIVE_PREFIX}/libexec/moc-qt6"
then
  # For compatibility with crosser < 2.5.
  if ! ln -s "${DIST_NATIVE_PREFIX}/libexec/moc" "${DIST_NATIVE_PREFIX}/libexec/moc-qt6"
  then
    log_error "Failed to make moc-qt6 compatibility link"
    exit 1
  fi
fi

fi

GDKPBL="lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
WGDKPBL="${GDKPBL//\//\\}"

log_write 1 "Creating crosser.txt"
(
  echo "# Dllstack"
  echo "# ========================="
  echo "CrosserVersion=\"${CROSSER_VERSION}\""
  echo "CrosserFeatureLevel=\"${CROSSER_FEATURE_LEVEL}\""
  echo "CrosserSetup=\"${CROSSER_SETUP}\""
  echo "CrosserSet=\"${CROSSER_VERSIONSET}\""
  echo "CrosserBuilt=\"$(date +"%d.%m.%Y")\""
  echo
  echo "# -------------------------"
  if test "$VERSION_GTK3" != "0"
  then
    echo "CROSSER_GTK3=\"yes\""
  else
    echo "CROSSER_GTK3=\"no\""
  fi
  echo "CROSSER_GTK4=\"${CROSSER_GTK4}\""
  echo "CROSSER_GTK5=\"no\""
  echo "CROSSER_QT5=\"${CROSSER_QT5}\""
  echo "CROSSER_QT6=\"${CROSSER_QT6}\""
  echo "CROSSER_SDL2=\"${CROSSER_SDL2}\""
  echo "CROSSER_SDL3=\"no\""
  echo "CROSSER_READLINE=\"${CROSSER_READLINE}\""
  echo "CROSSER_SFML=\"${CROSSER_SFML}\""
  echo
  echo "# Deprecated entries"
  echo "# -------------------------"
  echo "CROSSER_QT=\"${CROSSER_QT5}\""
  echo "CROSSER_GTK2=\"no\""
) > "${DLLSPREFIX}/crosser.txt"

log_write 1 "Copying license information"
if ! mkdir -p "${DLLSPREFIX}/license" ||
   ! cp "${CROSSER_MAINDIR}/license/crosser.license" "${DLLSPREFIX}/license/" ||
   ! cp "${CROSSER_MAINDIR}/COPYING" "${DLLSPREFIX}/license/"
then
  log_error "Failed to copy license information"
  exit 1
fi

log_write 1 "Creating configuration files"

if test "${VERSION_GTK3}" != "0"
then
  mkdir -p "${DLLSPREFIX}/etc/gtk-3.0"
  (
    echo -n -e "[Settings]\r\n"
    echo -n -e "gtk-fallback-icon-theme = hicolor\r\n"
    echo -n -e "gtk-button-images = true\r\n"
    echo -n -e "gtk-menu-images = true\r\n"
  ) > "${DLLSPREFIX}/etc/gtk-3.0/settings.ini"
fi

log_write 1 "Creating setup.bat"
(
  echo -n -e "bin\\\glib-compile-schemas.exe share\\\glib-2.0\\\schemas\r\n"
  if test "${VERSION_GDK_PIXBUF}" != "0"
  then
    echo -n -e "bin\\\gdk-pixbuf-query-loaders.exe > \"${WGDKPBL}\"\r\n"
  fi
  if test "${VERSION_GTK4}" != "0"
  then
    echo -n -e "bin\\\gtk4-update-icon-cache.exe share\\\icons\\Adwaita\r\n"
    echo -n -e "bin\\\gtk4-update-icon-cache.exe share\\\icons\\hicolor\r\n"
  elif test "${VERSION_GTK3}" != "0"
  then
    echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\Adwaita\r\n"
    echo -n -e "bin\\\gtk-update-icon-cache.exe share\\\icons\\hicolor\r\n"
  fi
  echo -n -e "if not exist etc\\\crosser mkdir etc\\\crosser\r\n"
  echo -n -e "echo done > etc\\\crosser\\\setup.state\r\n"
) > "${DLLSPREFIX}/setup.bat"

log_write 1 "Creating launch.bat"
(
  echo -n -e "set WINSTACK_ROOT=%~dp0\r\n"
  echo -n -e "set PATH=%~dp0\\\lib;%~dp0\\\bin;%PATH%\r\n"
  if test "${CROSSER_QT5}" = "yes"
  then
    echo -n -e "set QT_PLUGIN_PATH=%~dp0\\\qt5\\\plugins\r\n"
  elif test "${CROSSER_QT6}" = "yes"
  then
    echo -n -e "set QT_PLUGIN_PATH=%~dp0\\\qt6\\\plugins\r\n"
  fi
) > "${DLLSPREFIX}/launch.bat"

log_write 1 "IMPORTANT: Remember to run setup.bat when installing to target"

log_write 1 "SUCCESS"
