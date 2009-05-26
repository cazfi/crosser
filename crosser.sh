#!/bin/bash

# crosser.sh: Generic toolchain builder.
#
# (c) 2008-2009 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

MAINDIR=$(cd $(dirname $0) ; pwd)

STEP="setup"
STEPADD="   "

if test "x$1" = "x-h" || test "x$1" = "x--help" ; then
  echo "Usage: $(basename $0) [target setup name] [steps] [versionset]"
  exit 0
fi

# In order to give local setup opportunity to override versions,
# we have to load versionset before build_setup.conf
# helpers.sh requires environment to be set up by build_setup.conf.
if test "x$3" != "x" ; then
  VERSIONSET="$3"
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
. $MAINDIR/scripts/buildfuncs.sh

if ! log_init
then
  exit 1
fi

if test "x$ERR_MSG" != "x"
then
  log_error "$ERR_MSG"
  exit 1
fi

if test $(id -u) == 0
then
  log_error "Do not run crosser.sh as root. That can destroy your system."
  exit 1
fi

if test "x$1" != "x" ; then
  SETUP="$1"
else
  SETUP="i686-linux"
  log_write 1 "No setup selected, defaulting to \"$SETUP\""
fi

if test "x$2" != "x" ; then
  STEPPARAM="$2"
else
  if test "x$FORCERM" != "xyes"
  then
    ANSWER="unknown"

    while test "x$ANSWER" != "xyes" && test "x$ANSWER" != "xno"
    do
      echo "You gave no steps. Building everything from scratch will take very long time."
      echo "Are you sure you want to continue?"
      echo "yes/no"
      echo -n "> "
      read ANSWER
      case "x$ANSWER" in
        xyes|xy|xYES|xYes) ANSWER="yes" ;;
        xno|XNO|xNo) ANSWER="no" ;;
        *) echo "Please answer \"yes\" or \"no\"." ;;
      esac
    done

    if test "x$ANSWER" != "xyes"
    then
      exit 1
    fi
  fi
  log_write 1 "No build steps defined, building everything"
  STEPPARAM="native:sdl"
fi

. $MAINDIR/steps/stepfuncs.sh

STEPLIST="$(parse_steplist $STEPPARAM)"

if test $? -ne 0
then
  log_error "Illegal step definition \"$STEPPARAM\""
  exit 1
fi

# Setup step variables
. $MAINDIR/steps/stepset.sh

if ! test -e "$MAINDIR/setups/$SETUP.conf" ; then
  log_error "Can't find setup \"$SETUP.conf\""
  exit 1
fi
source "$MAINDIR/setups/$SETUP.conf"

if test "x$LIBC_MODE" = "xnone"
then
  log_error "Configuration \"$SETUP\" cannot be used with crosser.sh"
  exit 1
fi

if test "x$TARGET_VENDOR" = "x"
then
  TARGET="$TARGET_ARCH-$TARGET_OS"
else
  TARGET="$TARGET_ARCH-$TARGET_VENDOR-$TARGET_OS"
fi

if ! source $MAINDIR/setups/native.sh ; then
  log_error "Failed to read $MAINDIR/setups/native.sh"
  exit 1
fi
NATIVE_ARCH="$TMP_ARCH"
NATIVE_VENDOR="$TMP_VENDOR"
NATIVE_OS="$TMP_OS"

if test "x$NATIVE_VENDOR" = "x"
then
  BUILD="$NATIVE_ARCH-$NATIVE_OS"
else
  BUILD="$NATIVE_ARCH-$NATIVE_VENDOR-$NATIVE_OS"
fi

NATIVE_PREFIX=$(setup_prefix_default "$HOME/.crosser/$CROSSER_VERSION/host" "$NATIVE_PREFIX")

CH_ERROR="$(check_crosser_env $NATIVE_PREFIX native)"
if test "x$CH_ERROR" != "x" && test "x$STEP_NATIVE" != "xyes" ; then
  log_error "$CH_ERROR"
  log_error "Step 'native' for building environment is not enabled."
  exit 1
fi

# If native build, and cross-compile is not already being forced
if test "x$TARGET" = "x$BUILD" && test "x$CROSS_OFF" = "x" ; then
  CROSS_OFF=yes
  DEFPREFIX="$HOME/.crosser/$CROSSER_VERSION/native"
else
  DEFPREFIX="$HOME/.crosser/$CROSSER_VERSION/$TARGET-$LIBC_MODE"
fi

PREFIX=$(setup_prefix_default "$DEFPREFIX" "$PREFIX")
SYSPREFIX="$PREFIX/target"
CROSSPREFIX="$PREFIX/crosstools"

if test "x$CROSS_OFF" != "xyes"
then
  CH_ERROR="$(check_crosser_env $PREFIX $TARGET)"
  if test "x$CH_ERROR" != "x" &&
     test "x$STEP_CHAIN" != "xyes" &&
     ( test "x$STEP_BASELIB" = "xyes" ||
       test "x$STEP_GTK" = "xyes" ||
       test "x$STEP_SDL" = "xyes" )
  then
    log_error "$CH_ERROR"
    log_error "Step 'chain' for building environment is not enabled."
    exit 1
  fi
fi

#############################################################################

# Build glibc using cross-compiler
#
# $1   - Component to compile
# $2   - Sourcedir in source hierarchy
# $3   - Configure options
# $4   - Make targets
# $5   - glibc pass
build_glibc() {
  CONFOPTIONS="--build=$BUILD --host=$TARGET --target=$TARGET --prefix=/usr $3 --disable-nls"

  export CFLAGS="-O2 $CFLAGS_GLIBC"
  export CPPFLAGS=""
  export LDFLAGS=""

  if ! build_generic "tgt-$1" "$2" "$CONFOPTIONS" "$4 install_root=$SYSPREFIX"
  then
    return 1
  fi

  if test "x$5" = "xheaders"
  then
    log_write 3 "  Copying dummy headers"

    if ! cp "$MAINBUILDDIR/tgt-$1/bits/stdio_lim.h" \
            "$SYSPREFIX/usr/include/bits/"
    then
      log_error "Failed to copy initial stdio_lim.h"
      return 1
    fi

    if ! touch "$SYSPREFIX/usr/include/gnu/stubs.h"
    then
      log_error "Failed to create dummy stubs.h"
      return 1
    fi
  fi
}

# Build zlib using cross-compiler
#
# $1 - Component name
# $2 - Source dir in source hierarchy
# $3 - Configure options
# $4 - Make targets
build_zlib() {
  if test "x$CROSS_OFF" = "xyes"
  then
    export CC=gcc
    export RANLIB=ranlib
    export AR=ar
  else
    export CC=$TARGET-gcc
    export RANLIB=$TARGET-ranlib
    export AR=$TARGET-ar
  fi

  export CFLAGS=""
  export CPPFLAGS="-isystem $SYSPREFIX/include"
  export LDFLAGS="-L$SYSPREFIX/lib"

  CONFOPTIONS="--prefix=$SYSPREFIX $3"

  # TODO: zlib build doesn't like this variable, check why.
  unset TARGET_ARCH

  build_generic "$1" "$2" "$CONFOPTIONS" "$4" yes
}

# Creates base directories to native hierarchy
#
create_host_dirs()
{
  # Remove old
  if ! remove_dir "$NATIVE_PREFIX"
  then
    return 1
  fi

  if ! mkdir -p $NATIVE_PREFIX/usr/include
  then
    log_error "Failed to create host directories under \"$NATIVE_PREFIX\""
    return 1
  fi
}

# Creates base directories to cross-chain hierarchy
#
create_target_dirs()
{
  if ! mkdir -p $SYSPREFIX/etc         ||
     ! mkdir -p $SYSPREFIX/include     ||
     ! mkdir -p $SYSPREFIX/usr/include ||
     ! mkdir -p $SYSPREFIX/usr/lib
  then
    log_error "Failed to create target directories under \"$PREFIX\""
    return 1
  fi
}

# Install kernel or kernel headers
#
# [$1] - "full" - build kernel. Default is to only install headers
#
kernel_setup() {
  if test "x$1" = "xfull"
  then
    log_write 1 "Kernel setup"
    log_packet "Kernel"
  else
    log_write 1 "Kernel header setup"
    log_packet "Kernel headers"
  fi

  # Kernel may have been unpacked already in chain step
  if ! test -d $MAINSRCDIR/linux-$VERSION_KERNEL &&
     ! unpack_component linux $VERSION_KERNEL
  then
    log_error "Failed to unpack kernel"
    return 1
  fi

  if ! (
    cd $MAINSRCDIR/linux-$VERSION_KERNEL

    if test -f $PACKETDIR/kernel-$TARGET.config ; then
      cp $PACKETDIR/kernel-$TARGET.config .config
      KCONFTARGET=silentoldconfig
    else
      KCONFTARGET=defconfig
    fi

    if test "x$CROSS_OFF" != "xyes" ; then
      export CROSSPARAM="CROSS_COMPILE=$TARGET-"
      if test "x$KERN_ARCH" = "x" ; then
         KERN_ARCH=$TARGET_ARCH
      fi
      KERN_PARAM="ARCH=$KERN_ARCH"
    fi

    MAKEPARAMS="$CROSSPARAM $KERN_PARAM $KCONFTARGET prepare"

    log_write 3 "  Make params: $MAKEPARAMS"

    if ! make $MAKEPARAMS \
	           2>>$MAINLOGDIR/stderr.log >>$MAINLOGDIR/stdout.log
    then
      log_error "Kernel prepare failed"
      return 1
    fi

    if test "x$1" = "xfull"
    then
      MAKETARGETS="bzImage modules modules_install"
      log_write 1 "Building linux kernel"
    else
      MAKETARGETS="headers_install"
    fi
    MAKEPARAMS="$CROSSPARAM $KERN_PARAM INSTALL_HDR_PATH=$SYSPREFIX/usr INSTALL_MOD_PATH=$SYSPREFIX $MAKETARGETS"

    log_write 3 "  Make params: $MAKEPARAMS"
    if ! make $MAKEPARAMS \
                2>>$MAINLOGDIR/stderr.log >>$MAINLOGDIR/stdout.log
    then
      if test "x$1" = "xfull"
      then
        log_error "Kernel build failed"
      else
        log_error "Kernel headers install failed"
      fi
      return 1
    fi
  ) then
    return 1
  fi
}

# Create link to one host command in hostbin directory
#
# $1 - Command to link
# $2 - Required ('no')
link_host_command() {
  CMDDIRS="/usr/local/sbin /usr/sbin /sbin"
  CMDPATH="$(which $1)"

  if test "x$CMDPATH" = "x"
  then
    for CMDDIR in $CMDDIRS
    do
      if test "x$CMDPATH" = "x" && test -x "$CMDDIR/$1"
      then
        CMDPATH="$CMDDIR/$1"
      fi
    done
    if test "x$CMDPATH" = "x"
    then
      if test "x$2" != "xno"
      then
        log_error "Cannot find host command $1"
        return 1
      else
        return 0
      fi
    fi
  fi

  if ! ln -s $CMDPATH $NATIVE_PREFIX/hostbin/
  then
    log_error "Failed to make symbolic link to host command $1"
    return 1
  fi
}

# Setup hostbin directory
#
# 0 - Success
# 1 - Failure
setup_host_commands() {
  # Absolutely required commands
  HOST_COMMANDS_REQ="mkdir touch true false chmod rm which sed grep expr cat echo sort mv cp ln cmp test comm ls rmdir tr date uniq sleep diff basename dirname tail head env uname cut readlink od egrep fgrep wc make find pwd tar m4 awk getconf expand perl bison bzip2 flex makeinfo install whoami depmod wget pod2man msgfmt pkg-config sh glib-genmarshal hostname dnsdomainname mktemp"
  # Usefull commands
  HOST_COMMANDS_TRY="dpkg-source md5sum gpg sha1sum sha256sum gzip gunzip patch"

  log_write 1 "Setting up hostbin"

  if ! mkdir -p $NATIVE_PREFIX/hostbin ; then
    log_error "Cannot create directory $PREFIX/hostbin"
    return 1
  fi

  for HOST_CMD in $HOST_COMMANDS_REQ
  do
    if ! link_host_command $HOST_CMD
    then
      return 1
    fi
  done

  for HOST_CMD in $HOST_COMMANDS_TRY
  do
    if ! link_host_command $HOST_CMD no
    then
      return 1
    fi
  done
}

# Build dummy glibc objects
#
dummy_glibc_objects() {
  log_write 1 "Generating dummy c-lib objects"

  if ! mkdir $MAINBUILDDIR/crt ; then
     return 1
  fi

  if ! (
    cd $MAINBUILDDIR/crt

    echo "/* Build dummy crt.o object from this comment */" > crt.c

    if ! $TARGET-gcc -c crt.c ; then
       log_error "crt.o build failed"
       return 1
    fi
    if ! $TARGET-gcc -c -shared -fPIC $MAINDIR/scripts/dummyclib.c -o libc.so \
         2>>$MAINLOGDIR/stderr.log >>$MAINLOGDIR/stdout.log
    then
        log_error "Failed to build dummy libc.so"
       return 1
    fi

    if ! test -e $SYSPREFIX/usr/lib/crt1.o &&
       ! cp crt.o $SYSPREFIX/usr/lib/crt1.o ; then
       log_error "Failed to copy crt1.o"
       return 1
    fi
    if ! test -e $SYSPREFIX/usr/lib/crti.o &&
       ! cp crt.o $SYSPREFIX/usr/lib/crti.o ; then
       log_error "Failed to copy crti.o"
       return 1
    fi
    if ! test -e $SYSPREFIX/usr/lib/crtn.o &&
       ! cp crt.o $SYSPREFIX/usr/lib/crtn.o ; then
       log_error "Failed to copy crtn.o"
       return 1
    fi
    if ! test -e $SYSPREFIX/usr/lib/libc.so &&
       ! cp libc.so $SYSPREFIX/usr/lib/libc.so ; then
       log_error "Failed to copy libc.so"
       return 1
    fi

  ) ; then
    return 1
  fi
}

# Prepare binutils source tree
#
prepare_binutils_src() {
  if ! unpack_component binutils     $VERSION_BINUTILS            ||
     ! ( is_greater_version $VERSION_BINUTILS 2.18     ||
        (  patch_src binutils-$VERSION_BINUTILS binutils_makeinfo &&
           cd $MAINSRCDIR/binutils-$VERSION_BINUTILS && autoconf ))
  then
    log_error "Binutils setup failed"
    return 1
  fi
}

# Basic preparation of gcc source tree
#
prepare_gcc_src() {
  if ! unpack_component gcc          $VERSION_GCC      ||
     ! unpack_component gmp          $VERSION_GMP      ||
     ! unpack_component mpfr         $VERSION_MPFR
  then
    log_error "Unpacking failed"
    exit 1
  fi

  if ! (! cmp_versions $VERSION_GCC 4.3.1 ||
        patch_src gcc-$VERSION_GCC gcc_cldconf )
  then
    log_error "GCC patching failed"
    exit 1
  fi

  if ! ln -s ../mpfr-$VERSION_MPFR $MAINSRCDIR/gcc-$VERSION_GCC/mpfr ||
     ! ln -s ../gmp-$VERSION_GMP $MAINSRCDIR/gcc-$VERSION_GCC/gmp
  then
    log_error "Creation of links to additional gcc modules failed"
    exit 1
  fi
}

if test "x$TARGET" = "x$BUILD" && test "x$CROSS_OFF" = "x"
then
  CROSS_OFF=yes
fi

if test "x$CROSS_OFF" = "xyes"
then
  log_write 2 "Building to native target. Cross-compilers will not be built or used"
fi

log_write 2 "Native tools: \"$NATIVE_PREFIX\""
log_write 2 "Toolchain:    \"$PREFIX\""
log_write 2 "Target:       \"$TARGET\""
log_write 2 "Src:          \"$MAINSRCDIR\""
log_write 2 "Log:          \"$MAINLOGDIR\""
log_write 2 "Build:        \"$MAINBUILDDIR\""
log_write 2 "Setup:        \"$SETUP\""
log_write 2 "Versionset:   \"$VERSIONSET\""
log_write 2 "Steps:        \"$STEPLIST\""
log_write 2 "c-lib:        \"$LIBC_MODE\""

if ! remove_dir "$MAINBUILDDIR" ||
   ! remove_dir "$MAINSRCDIR"   ||
   ! (test "x$STEP_NATIVE" != "xyes" || remove_dir "$NATIVE_PREFIX") ||
   ! (test "x$STEP_CHAIN"  != "xyes" || remove_dir "$PREFIX")
then
  log_error "Failed to remove old directories"
  exit 1
fi

if ! mkdir -p $MAINSRCDIR || ! mkdir -p $MAINBUILDDIR
then
  log_error "Cannot create main directories"
  exit 1
fi

if ! packetdir_check
then
  log_error "Packetdir missing"
  exit 1
fi

if test "x$CROSSER_DOWNLOAD" = "xyes"
then
  if ! ( cd $PACKETDIR && $MAINDIR/scripts/download_packets.sh "$STEPPARAM" )
  then
    log_error "Download failed"
    exit 1
  fi
fi

if test "x$STEP_NATIVE" = "xyes" ; then
  STEP="native"
  STEPADD="  "

  BASEVER_LIBTOOL="$(basever_libtool $VERSION_LIBTOOL)"

  # Build of latter tools uses earlier tools
  export PATH=$NATIVE_PREFIX/bin:$PATH

  if ! create_host_dirs     ||
     ! unpack_component libtool  $VERSION_LIBTOOL             ||
     ! build_for_host   libtool  libtool-$BASEVER_LIBTOOL     ||
     ! unpack_component gawk     $VERSION_GAWK                ||
     ! build_for_host   gawk     gawk-$VERSION_GAWK           ||
     ! unpack_component autoconf $VERSION_AUTOCONF            ||
     ! build_for_host   autoconf autoconf-$VERSION_AUTOCONF   ||
     ! unpack_component automake $VERSION_AUTOMAKE            ||
     ! build_for_host   automake automake-$VERSION_AUTOMAKE   ||
     ! unpack_component Python   $VERSION_PYTHON              ||
     ! build_for_host   Python   Python-$VERSION_PYTHON       ||
     ! unpack_component gtk-doc  $VERSION_GTK_DOC             ||
     ! build_for_host   gtk-doc  gtk-doc-$VERSION_GTK_DOC     ||
     ! unpack_component pkg-config $VERSION_PKG_CONFIG            ||
     ! build_for_host   pkg-config pkg-config-$VERSION_PKG_CONFIG ||
     ! prepare_binutils_src                                   ||
     ! build_for_host binutils binutils-$VERSION_BINUTILS     \
     "--with-tls --enable-stage1-languages=all"               ||
     ! prepare_gcc_src                                        ||
     ! build_for_host gcc gcc-$VERSION_GCC                    \
     "--enable-languages=c,c++ --disable-multilib --with-tls"
  then
     crosser_error "Failed to build native compiler for host"
     exit 1
  fi

  if ! setup_host_commands
  then
    crosser_error "Cannot enable selected host commands"
    exit 1
  fi

  write_crosser_env "$NATIVE_PREFIX" Native
fi

# None of these path variables contain original $PATH.
# This limits risk of host system commands from 'leaking' to our environments.
# Commands that are safe to use from host system are accessed through hostbin.
PATH_NATIVE="$NATIVE_PREFIX/bin:$NATIVE_PREFIX/hostbin"
PATH_CROSS="$CROSSPREFIX/bin:$PATH_NATIVE"

if test "x$CROSSER_CCACHE" != "x" ; then
  PATH_NATIVE="$CROSSER_CCACHE:$PATH_NATIVE"
  PATH_CROSS="$CROSSER_CCACHE:$PATH_CROSS"
fi

if ! create_target_dirs ; then
  crosser_error "Failed to create target dirs"
  exit 1
fi

if test "x$STEP_CHAIN" = "xyes" && test "x$CROSS_OFF" != "xyes"
then
  STEP="chain(1)"
  STEPADD=""

  export CCACHE_DIR="$NATIVE_PREFIX/.ccache"

  # If native step already executed, these preparations are done.
  if test "x$STEP_NATIVE" != "xyes"
  then
    if ! prepare_binutils_src ||
       ! prepare_gcc_src
    then
      exit 1
    fi
  fi

  if test "x$BUILD" = "x$TARGET" && test "x$LIBC_MODE" = "xglibc"
  then
    export PATH="$PATH_NATIVE:$PATH"
    hash -r
    # Prepare kernel sources while we are still using compiler with
    # original sysroot
    if ! kernel_setup
    then
      crosser_error "Kernel header setup failed"
      exit 1
    fi
  fi

  export PATH="$PATH_CROSS"
  hash -r

  if ! build_with_native_compiler binutils binutils-$VERSION_BINUTILS \
        "--with-sysroot=$SYSPREFIX --with-tls --enable-stage1-languages=all"
  then
    crosser_error "Binutils build failed"
    exit 1
  fi

  if ! ln -s include "$SYSPREFIX/sys-include" ; then
    log_error "Failed creation of sys-include link."
    exit 1
  fi

  if test "x$LIBC_MODE" = "xnewlib"
  then

    if ! unpack_component newlib       $VERSION_NEWLIB ||
       ! patch_src newlib-$VERSION_NEWLIB newlib_gloss_ldflags
    then
      crosser_error "Newlib unpacking failed"
      exit 1
    fi

    if ! ln -s ../newlib-$VERSION_NEWLIB/newlib \
               $MAINSRCDIR/gcc-$VERSION_GCC ||
       ! ln -s ../newlib-$VERSION_NEWLIB/libgloss \
               $MAINSRCDIR/gcc-$VERSION_GCC
    then
      crosser_error "Creation of newlib links failed"
      exit 1
    fi

    log_write 1 "Copying initial newlib headers"
    if ! cp -R "$MAINSRCDIR/newlib-$VERSION_NEWLIB/newlib/libc/include" \
               "$SYSPREFIX/"
    then
      crosser_error "Failed initial newlib headers copying."
      exit 1
    fi

    if ! build_with_native_compiler gcc gcc-$VERSION_GCC \
          "--enable-languages=c,c++ --with-newlib --with-gnu-as --with-gnu-ld --with-tls --with-sysroot=$SYSPREFIX --disable-multilib --enable-threads --disable-decimal-float" \
          "all-gcc install-gcc all-target-zlib install-target-zlib all-target-newlib install-target-newlib all-target-libgloss install-target-libgloss all-target-libgcc install-target-libgcc"
    then
      crosser_error "Build of cross-compiler failed"
      exit 1
    fi
  fi

  if test "x$LIBC_MODE" = "xglibc"
  then

    # Initial cross-compiler                                                                      
    if ! build_with_native_compiler gcc gcc-$VERSION_GCC \
        "--enable-languages=c --with-gnu-as --with-gnu-ld --with-tls --with-sysroot=$SYSPREFIX --disable-multilib" \
        "all-gcc install-gcc"
    then
      crosser_error "Build of initial cross-compiler failed"
      exit 1
    fi

    if test "x$BUILD" != "x$TARGET" && ! kernel_setup
    then
      crosser_error "Kernel header setup failed"
      exit
    fi

    LIBCNAME=glibc
    LIBCVER=$VERSION_GLIBC
    LIBCDIR=$LIBCNAME-$LIBCVER

    if ! unpack_component $LIBCNAME       $LIBCVER          ||
       ! unpack_component $LIBCNAME-ports $LIBCVER $LIBCDIR
    then
      crosser_error "$LIBCNAME unpacking failed"
      exit 1
    fi

    if ! (is_minimum_version $LIBCVER 2.8 ||
          patch_src $LIBCDIR glibc_upstream_finc)                                 ||
       ! (is_minimum_version $LIBCVER 2.8 ||
          patch_src $LIBCDIR/$LIBCNAME-ports-$LIBCVER glibc_ports_arm_docargs)    ||
       ! (is_minimum_version $LIBCVER 2.8 ||
          patch_src $LIBCDIR/$LIBCNAME-ports-$LIBCVER glibc_ports_arm_pageh_inc)  ||
       ! patch_src $LIBCDIR/$LIBCNAME-ports-$LIBCVER glibc_ports_arm_tlsinc       ||
       ! (is_smaller_version $LIBCVER 2.9 ||
          patch_src $LIBCDIR/$LIBCNAME-ports-$LIBCVER glibc_upstream_arm_sigsetjmp)
    then
      crosser_error "$LIBCNAME patching failed"
      exit 1
    fi

#    if ! autogen_component eglibc $VERSION_EGLIBC "autoconf"
#    then
#      crosser_error "Eglibc autogen failed"
#      exit 1
#    fi

    log_write 1 "Installing initial $LIBCNAME headers"
    if ! build_glibc $LIBCNAME $LIBCDIR \
           "--with-tls --enable-add-ons=$LIBCNAME-ports-$LIBCVER --disable-sanity-checks --with-sysroot=$SYSPREFIX --with-headers=$SYSPREFIX/usr/include" \
           "install-headers install-bootstrap-headers=yes" "headers"
    then
      log_error "Failed to install initial $LIBCNAME headers"
      exit 1
    fi

    if ! dummy_glibc_objects
    then
      log_error "Failed to build dummy $LIBCNAME objects"
      exit 1
    fi

    STEP="chain(2)"

    if ! build_with_native_compiler gcc gcc-$VERSION_GCC \
          "--disable-multilib --enable-languages=c --with-tls --with-sysroot=$SYSPREFIX --disable-threads --disable-libssp --disable-libgomp --disable-libmudflap"
    then
      crosser_error "Failed to build phase 2 cross-compiler"
      exit 1
    fi

    if ! build_glibc $LIBCNAME $LIBCDIR \
             "--with-tls --with-sysroot=$SYSPREFIX --with-headers=$SYSPREFIX/usr/include --enable-add-ons=$LIBCNAME-ports-$LIBCVER,nptl" \
             "all install"
    then
      crosser_error "Failed to build final $LIBCNAME"
      exit 1
    fi

    STEP="chain(3)"

    if ! build_with_native_compiler gcc gcc-$VERSION_GCC \
          "--disable-multilib --enable-languages=c,c++ --with-tls --with-sysroot=$SYSPREFIX --enable-threads"
    then
      crosser_error "Failed to build final cross-compiler"
      exit 1
    fi

  fi

  write_crosser_env "$PREFIX" "$TARGET"

  generate_setup_scripts $PREFIX
else # STEP_CHAIN
  # Set PATH only if it's not already correct to avoid unnecessary hash reset.
  export PATH="$PATH_CROSS"
  hash -r
fi   # STEP_CHAIN

export CCACHE_DIR="$PREFIX/.ccache"

export PKG_CONFIG_LIBDIR="$SYSPREFIX/lib/pkgconfig:$SYSPREFIX/usr/lib/pkgconfig"

if test "x$STEP_BASELIB" = "xyes"
then
  STEP="baselib"
  STEPADD=" "

  if ! unpack_component  zlib         $VERSION_ZLIB           ||
     ! unpack_component  libpng       $VERSION_PNG
  then
    log_error "Baselib unpacking failed"
    exit 1
  fi

  # Some patches work only when compiling for Windows target and
  # thus are used in libstack.sh only
  if ! patch_src zlib               zlib_cctest               ||
     ! patch_src zlib               zlib_seeko
  then
    error_log "Baselib patching failed"
    exit 1
  fi

  if ! build_zlib                zlib    zlib                 \
        "--shared"                                            ||
     ! build_with_cross_compiler libpng  libpng-$VERSION_PNG
  then
    crosser_error "Baselib build failed"
    exit 1
  fi
fi

if test "x$STEP_GTK" = "xyes"
then
  STEP="gtk"
  STEPADD="     "

  if test "x$LIBC_MODE" != "xglibc"
  then
    log_write 1 "Step gtk not available for $LIBC_MODE based builds, skipping"
  else
    GLIB_VARS="$(read_configure_vars glib)"
    log_write 4 "Glib variables: $GLIB_VARS"

    if ! unpack_component          glib          $VERSION_GLIB                           ||
       ! ( ! cmp_versions $VERSION_GLIB 2.18.0    ||
           ( patch_src glib-$VERSION_GLIB glib_gmoddef &&
             autogen_component glib    $VERSION_GLIB "aclocal automake autoconf" ))      ||
       ! build_with_cross_compiler glib          glib-$VERSION_GLIB                      \
         "--prefix=/usr $GLIB_VARS"
    then
      crosser_error "Glib build failed"
      exit 1
    fi

    STEP="gtk(ft1)"
    STEPADD=""
    if ! unpack_component          freetype      $VERSION_FREETYPE                       ||
       ! build_with_cross_compiler freetype      freetype-$VERSION_FREETYPE              \
         "--prefix=$PREFIX/interm" "" "/"
    then
      crosser_error "Intermediate freetype build failed"
      exit 1
    fi

    STEP="gtk(ft2)"
    STEPADD=""
    if ! build_with_cross_compiler freetype      freetype-$VERSION_FREETYPE
    then
      crosser_error "Target freetype build failed"
      exit 1
    fi

    STEP="gtk"
    STEPADD="     "
    if ! unpack_component          expat         $VERSION_EXPAT                          ||
       ! build_with_cross_compiler expat         expat-$VERSION_EXPAT                    ||
       ! unpack_component          pixman        $VERSION_PIXMAN                         ||
       ! build_with_cross_compiler pixman        pixman-$VERSION_PIXMAN                  \
         "--prefix=/usr --disable-gtk"                                                   ||
       ! unpack_component          fontconfig    $VERSION_FONTCONFIG                     ||
       ! patch_src fontconfig-$VERSION_FONTCONFIG fontconfig_cross                       ||
       ! patch_src fontconfig-$VERSION_FONTCONFIG fontconfig_libtool                     ||
       ! autogen_component fontconfig $VERSION_FONTCONFIG                                \
         "libtoolize aclocal automake autoconf"                                          ||
       ! build_with_cross_compiler fontconfig                                            \
          fontconfig-$VERSION_FONTCONFIG                                                 \
          "--prefix=/usr --with-freetype-config=$PREFIX/interm/bin/freetype-config --with-arch=$TARGET"
    then
      crosser_error "gtk+ chain build failed"
      exit 1
    fi
  fi
fi

if test "x$STEP_SDL" = "xyes"
then
  STEP="sdl"
  STEPADD="     "

  if test "x$LIBC_MODE" != "xglibc"
  then
    log_write 1 "Step sdl not available for $LIBC_MODE based builds, skipping"
  else

    if ! kernel_setup full                                                ||
       ! unpack_component          svgalib $VERSION_SVGALIB               ||
       ! patch_src svgalib-$VERSION_SVGALIB svgalib_cfg                   ||
       ! patch_src svgalib-$VERSION_SVGALIB svgalib_gentoo_k26            ||
       ! patch_src svgalib-$VERSION_SVGALIB svgalib_gentoo_k2628          ||
       ! patch_src svgalib-$VERSION_SVGALIB svgalib_arm_outsb             ||
       ! patch_src svgalib-$VERSION_SVGALIB svgalib_nostrip               ||
       ! patch_src svgalib-$VERSION_SVGALIB svgalib_crossarch             ||
       ! build_svgalib             svgalib svgalib-$VERSION_SVGALIB       \
          "clean install"                                                 ||
       ! unpack_component          SDL       $VERSION_SDL                 ||
       ! build_with_cross_compiler SDL       SDL-$VERSION_SDL             ||
       ! unpack_component          SDL_image $VERSION_SDL_IMAGE           ||
       ! build_with_cross_compiler SDL_image SDL_image-$VERSION_SDL_IMAGE
    then
      crosser_error "sdl stack build failed"
      exit 1
    fi
  fi
fi

if test "x$STEP_TEST" = "xyes"
then
  STEP="test"
  STEPADD="    "

  # This is debugging step used only temporarily while testing.
fi

log_write 1 "SUCCESS"
