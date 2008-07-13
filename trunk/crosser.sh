#!/bin/bash

# crosser.sh: Generic toolchain builder.
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

MAINDIR=$(cd $(dirname $0) ; pwd)

STEP="setup"
STEPADD="  "

if test "x$1" = "x-h" || test "x$1" = "x--help" ; then
  echo "Usage: $(basename $0) [target setup name] [steps] [versionset] [c-lib]"
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

if ! log_init
then
  exit 1
fi

if test "x$ERR_MSG" != "x"
then
  log_error "$ERR_MSG"
  exit 1
fi

if test "x$1" != "x" ; then
  SETUP="$1"
else
  SETUP="i386-linux"
  log_write 1 "No setup selected, defaulting to \"$SETUP\""
fi

if test "x$2" != "x" ; then
  STEPPARAM="$2"
else
  log_write 1 "No build steps defined, building everything"
  STEPPARAM="all"
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

if test "x$4" = "x"
then
  log_write 1 "No c-lib selected, defaulting to newlib"
  LIBC_MODE="newlib"
else
  LIBC_MODE="$4"
  if test "x$LIBC_MODE" != "xnewlib" &&
     test "x$LIBC_MODE" != "xnone"
  then
    log_error "Unknown c-lib \"$LIBC_MODE\""
    exit 1
  fi
fi

if ! test -e "$MAINDIR/setups/$SETUP.conf" ; then
  log_error "Can't find setup \"$SETUP.conf\""
  exit 1
fi
source "$MAINDIR/setups/$SETUP.conf"

TARGET="$TARGET_ARCH-$TARGET_OS"

if ! source $MAINDIR/setups/native.sh ; then
  log_error "Failed to read $MAINDIR/setups/native.sh"
  exit 1
fi
NATIVE_ARCH="$TMP_ARCH"
NATIVE_OS="$TMP_OS"
BUILD="$NATIVE_ARCH-$NATIVE_OS"

NATIVE_PREFIX=$(setup_prefix_default "/usr/local/crosser/$CROSSER_VERSION/host" "$NATIVE_PREFIX")

if ! test -f $NATIVE_PREFIX/crosser/crosser.hierarchy &&
   test "x$STEP_NATIVE" != "xyes" ; then
  log_error "There's no native compiler environment present, and step 'native' for building one is not enabled."
  exit 1
fi

# If native build, and cross-compile is not already being forced
if test "x$TARGET" = "x$BUILD" && test "x$CROSS_OFF" = "x" ; then
  CROSS_OFF=yes
  DEFPREFIX="/usr/local/crosser/$CROSSER_VERSION/native"
else
  DEFPREFIX="/usr/local/crosser/$CROSSER_VERSION/$TARGET-$LIBC_MODE"
fi

PREFIX=$(setup_prefix_default "$DEFPREFIX" "$PREFIX")

if ! test -f $PREFIX/crosser/crosser.hierarchy &&
   test "x$STEP_CHAIN" != "xyes" &&
   test "x$STEP_BASELIB" = "xyes"
then
  log_error "Cross-compiler required, but not present nor being built. Enable step 'chain' to build one."
  exit 1
fi

#############################################################################

fail_out() {
  log_error "FAILING OUT"
  if test -d $PREFIX
  then
    generate_setup_scripts $PREFIX
  else
    log_error "Target directory not yet created - cannot generate environment for debugging"
  fi
  exit 1
}

# Generic function to compile one component
#
# $1 - Build directory in build hierarchy
# $2 - Sourcedir in source hierarchy
# $3 - Configure options
# $4 - Make targets
build_generic() {
  log_packet "$1"

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

  log_write 1 "Configuring: $2"
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

build_newlib_chain() {
  export CFLAGS=""

  CONFOPTIONS="--build=$BUILD --host=$BUILD --target=$TARGET --prefix=$PREFIX $3 --disable-nls"

  export LDFLAGS="-Wl,-rpath=$PREFIX -L$PREFIX"
  export CPPFLAGS="-I$PREFIX/include"

  if ! build_generic "newlib-$1" "$2" "$CONFOPTIONS" "$4"
  then
    return 1
  fi
}

build_newlib_compiler() {
  build_newlib_chain "$1" "$2" "$3" "$4"
}

build_with_newlib_compiler() {
  build_newlib_chain "$1" "$2" "$3" "$4"
}

# Build with compiler built in native step
#
# $1 - Component to compile
# $2 - Sourcedir in source hierarchy
# $3 - Configure options
# $4 - Make targets
build_with_native_compiler() {
  CONFOPTIONS="--build=$BUILD --host=$BUILD --target=$TARGET --prefix=$PREFIX $3 --disable-nls"

  export CFLAGS="-march=native"
  export LDFLAGS="-Wl,-rpath=$NATIVE_PREFIX/lib -L$NATIVE_PREFIX/lib"

  if ! build_generic "cross-$1" "$2" "$CONFOPTIONS" "$4"
  then
    return 1
  fi
}

# Build component using cross-compiler
#
# $1 - Component name
# $2 - Source dir in source hierarchy
# $3 - Configure options
# $4 - Make targets
build_with_cross_compiler() {
  CONFOPTIONS="--build=$BUILD --host=$TARGET --target=$TARGET --prefix=$PREFIX $3 --disable-nls"

  export LDFLAGS="-Wl,-rpath=$PREFIX -L$PREFIX"

  if ! build_generic "tgt-$1" "$2" "$CONFOPTIONS" "$4"
  then
    return 1
  fi
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

  if ! mkdir -p $NATIVE_PREFIX/crosser ||
     ! mkdir -p $NATIVE_PREFIX/usr/include
  then
    log_error "Failed to create host directories under \"$NATIVE_PREFIX\""
    return 1
  fi
}

# Creates base directories to cross-chain hierarchy
#
create_target_dirs()
{
  if ! mkdir -p $PREFIX/crosser     ||
     ! mkdir -p $PREFIX/etc         ||
     ! mkdir -p $PREFIX/include     ||
     ! mkdir -p $PREFIX/usr/include ||
     ! mkdir -p $PREFIX/usr/lib
  then
    log_error "Failed to create target directories under \"$PREFIX\""
    return 1
  fi
}

# Install kernel headers
#
# $1 - Target directory
kernel_header_setup() {
  log_write 1 "Kernel setup"

  KERN_INC_DIR="$1"

  if ! mkdir -p "$KERN_INC_DIR"
  then
    log_error "Failed to create directory \"$KERN_INC_DIR\""
    return 1
  fi

  if ! unpack_component linux $VERSION_KERNEL
  then
    log_error "Failed to unpack kernel"
    return 1
  fi

  if ! (
    cd $MAINSRCDIR/linux-$VERSION_KERNEL

    if test -f $MAINPACKETDIR/kernel-$TARGET.config ; then
      cp $MAINPACKETDIR/kernel-$TARGET.config .config
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

    ASMDIR=$(readlink include/asm)

    if test "x$ASMDIR" = "x" ; then
      log_error "Link linux-$VERSION_KERNEL/include/asm not found"
      return 1
    fi

    if ! cp -R include/linux "$KERN_INC_DIR/"       ||
       ! cp -R include/asm-generic "$KERN_INC_DIR/" ||
       ! cp -R include/$ASMDIR "$KERN_INC_DIR/asm"
    then
      log_error "Failed to copy kernel headers to $KERN_INC_DIR"
      return 1
    fi
  ) then
    return 1
  fi
}

run_ldconfig() {
  log_write 1 "Running ldconfig"

  if ! touch $PREFIX/etc/ld.so.conf ; then
    log_error "Failed to create ld.so.conf"
    return 1
  fi

  if ! $LDCONFIG -r $PREFIX ; then
    log_error "ldconfig failed"
    return 1
  fi
}

build_for_host() {
  CONFOPTIONS="--build=$BUILD --host=$BUILD --target=$BUILD --prefix=$NATIVE_PREFIX $3"
  export CFLAGS="-march=native -O2"
  export LDFLAGS="-Wl,-rpath=$NATIVE_PREFIX/lib -L$NATIVE_PREFIX/lib"

  if ! build_generic "host-$1" "$2" "$CONFOPTIONS" "$4"
  then
    return 1
  fi
}

# Create link to one host command in hostbin directory
#
# $1 - Command to link
# $2 - Required ('no')
link_host_command() {
  CMDPATH="$(which $1)"

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
  HOST_COMMANDS_REQ="mkdir touch true false chmod rm which sed grep expr cat echo sort mv cp ln cmp test comm ls rmdir tr date uniq sleep diff basename dirname tail head env uname cut readlink od egrep fgrep wc make find pwd tar m4 awk getconf perl bison bzip2 flex makeinfo wget pod2man msgfmt"
  # Usefull commands
  HOST_COMMANDS_TRY="dpkg-source md5sum gpg sha1sum sha256sum gzip gunzip patch"

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

# Prepare binutils source tree
#
prepare_binutils_src() {
  if ! unpack_component binutils     $VERSION_BINUTILS            ||
     ! ( is_greater_version $VERSION_BINUTILS 2.18     ||
         patch_src binutils-$VERSION_BINUTILS binutils_makeinfo ) ||
     ! (cd $MAINSRCDIR/binutils-$VERSION_BINUTILS && autoconf)
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

if test "x$CROSSER_DOWNLOAD" = "xyes"
then
  if ! $MAINDIR/download_packets.sh "$STEPPARAM"
  then
    log_error "Download failed"
    exit 1
  fi
fi

LDCONFIG=/sbin/ldconfig

if test "x$STEP_NATIVE" = "xyes" ; then
  STEP="native"
  STEPADD=" "

  if ! create_host_dirs     ||
     ! unpack_component libtool $VERSION_LIBTOOL ||
     ! build_for_host libtool libtool-$VERSION_LIBTOOL ||
     ! unpack_component gawk     $VERSION_GAWK                ||
     ! build_for_host   gawk     gawk-$VERSION_GAWK           ||
     ! unpack_component autoconf $VERSION_AUTOCONF            ||
     ! build_for_host   autoconf autoconf-$VERSION_AUTOCONF   ||
     ! unpack_component automake $VERSION_AUTOMAKE            ||
     ! build_for_host   automake automake-$VERSION_AUTOMAKE   ||
     ! prepare_binutils_src                                   ||
     ! build_for_host binutils binutils-$VERSION_BINUTILS     \
     "--with-tls --enable-stage1-languages=all"               ||
     ! prepare_gcc_src                                        ||
     ! build_for_host gcc gcc-$VERSION_GCC                    \
     "--enable-languages=c,c++ --disable-multilib --with-tls"
  then
     log_error "Failed to build native compiler for host"
     fail_out
  fi

  if ! setup_host_commands
  then
    log_error "Cannot enable selected host commands"
    fail_out
  fi

  echo "Setup:   Native"           >  "$NATIVE_PREFIX/crosser/crosser.hierarchy"
  echo "Version: $CROSSER_VERSION" >> "$NATIVE_PREFIX/crosser/crosser.hierarchy"
fi

# None of these path variables contain original $PATH.
# This limits risk of host system commands from 'leaking' to our environments.
# Commands that are safe to use from host system are accessed through hostbin.
PATH_NATIVE="$NATIVE_PREFIX/bin:$NATIVE_PREFIX/hostbin"
PATH_CROSS="$PREFIX/bin:$PATH_NATIVE"

if test "x$CROSSER_CCACHE" != "x" ; then
  PATH_NATIVE="$CROSSER_CCACHE:$PATH_NATIVE"
  PATH_CROSS="$CROSSER_CCACHE:$PATH_CROSS"
fi

if ! create_target_dirs ; then
  fail_out
fi

if test "x$STEP_CHAIN" = "xyes" && test "x$CROSS_OFF" != "xyes"
then
  STEP="chain"
  STEPADD="  "

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

  if test "x$BUILD" = "x$TARGET"
  then
    export PATH="$PATH_NATIVE:$PATH"
    hash -r
    # Prepare kernel sources while we are still using compiler with
    # original sysroot
    if ! kernel_header_setup "$PREFIX/include"
    then
      fail_out
    fi
  fi

  export PATH="$PATH_CROSS"
  hash -r

  if ! build_with_native_compiler binutils binutils-$VERSION_BINUTILS \
        "--with-sysroot=$PREFIX --with-tls --enable-stage1-languages=all"
  then
    fail_out
  fi

  # Initial cross-compiler
  if ! build_with_native_compiler gcc gcc-$VERSION_GCC \
      "--enable-languages=c --with-newlib --with-gnu-as --with-gnu-ld --with-tls --with-sysroot=$PREFIX --disable-multilib --enable-threads=posix" \
      "all-gcc install-gcc"
  then
    fail_out
  fi

  if test "x$BUILD" != "x$TARGET" && ! kernel_header_setup "$PREFIX/include"
  then
    fail_out
  fi

  if test "x$LIBC_MODE" = "xnewlib"
  then

    if ! unpack_component newlib       $VERSION_NEWLIB
    then
      log_error "Newlib unpacking failed"
      exit 1
    fi

    if ! ln -s ../newlib-$VERSION_NEWLIB/newlib \
               $MAINSRCDIR/gcc-$VERSION_GCC ||
       ! ln -s ../newlib-$VERSION_NEWLIB/libgloss \
               $MAINSRCDIR/gcc-$VERSION_GCC
    then
      log_error "Creation of newlib links failed"
      exit 1
    fi

    log_write 1 "Copying initial newlib headers"
    if ! cp -R "$MAINSRCDIR/newlib-$VERSION_NEWLIB/newlib/libc/include" \
               "$PREFIX/include"
    then
      log_error "Failed initial newlib headers copying."
      exit 1
    fi

    if ! ln -s include "$PREFIX/sys-include" ; then
      log_error "Failed creation of sys-include link."
      exit 1
    fi

    if ! build_newlib_compiler gcc gcc-$VERSION_GCC \
          "--enable-languages=c,c++ --with-newlib --with-gnu-as --with-gnu-ld --with-tls --with-sysroot=$PREFIX --disable-multilib --enable-threads --disable-decimal-float" \
          "all-gcc install-gcc all-target-zlib install-target-zlib all-target-newlib install-target-newlib all-target-libgloss install-target-libgloss all-target-libgcc install-target-libgcc"
    then
      fail_out
    fi

    echo "Setup:   $TARGET"          >  "$PREFIX/crosser/crosser.hierarchy"
    echo "Version: $CROSSER_VERSION" >> "$PREFIX/crosser/crosser.hierarchy"
  fi
else # STEP_CHAIN
  # Set PATH only if it's not already correct to avoid unnecessary hash reset.
  export PATH="$PATH_CROSS"
  hash -r
fi   # STEP_CHAIN

export CCACHE_DIR="$PREFIX/.ccache"

if test "x$STEP_BASELIB" = "xyes"
then
  STEP="baselib"
  STEPADD=""

  if ! unpack_component  zlib         $VERSION_ZLIB           ||
     ! unpack_component  libpng       $VERSION_PNG
  then
    log_error "Baselib unpacking failed"
    exit 1
  fi

  # Some patches work only when compiling for Windows target and
  # thus used in libstack.sh only
  if ! patch_src zlib               zlib_cctest               ||
     ! patch_src zlib               zlib_seeko
  then
    error_log "Baselib patching failed"
    exit 1
  fi

  if ! build_with_cross_compiler libpng libpng-$VERSION_PNG
  then
    fail_out
  fi
fi

generate_setup_scripts $PREFIX

log_write 1 "SUCCESS"
