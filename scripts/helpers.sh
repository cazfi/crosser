# No shebang, this script is not executed, but sourced.

# helpers.sh: Functions for Crosser
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test "x$MAINDIR" = "x"
then
  echo "helpers.sh: Mandatory environments variables missing! Have you sourced proper settings already?" >&2
  exit 1
fi

CROSSER_VERSION=$(tail -n 1 $MAINDIR/Version)
BUILD_DATE=$(date +"%d%m%y")

if test "x$LOGLEVEL_STDOUT" = "x" ; then
  LOGLEVEL_STDOUT=2
fi
if test "x$LOGLEVEL_FILE" = "x" ; then
  LOGLEVEL_FILE=4
fi

log_init() {
  if ! mkdir -p $MAINLOGDIR
  then
    echo "Failed to create logdir \"$MAINLOGDIR\"" >&2
    return 1
  fi

  log_write 0 "== Build starts =="
  rm -f $MAINLOGDIR/stderr.log
  rm -f $MAINLOGDIR/stdout.log
}

# Call this when starting build of new packet
# $1 - Packet name
log_packet() {
  # Create lines separating output from one packet build from the other
  echo "**** $1 ****" >> $MAINLOGDIR/stdout.log
  echo "**** $1 ****" >> $MAINLOGDIR/stderr.log
}

log_write() {
  DSTAMP=$(date +"%d.%m %H:%M")

  if test "x$1" = "x0" ; then
    echo >> $MAINLOGDIR/main.log
    log_write 1 "======================================"
  fi

  if test $1 -le $LOGLEVEL_FILE ; then
    echo -e "$DSTAMP $STEP:$STEPADD $2" >> $MAINLOGDIR/main.log
  fi

  if test $1 -le $LOGLEVEL_STDOUT ; then
    echo -e "$DSTAMP $STEP:$STEPADD $2"
  fi
}

log_error() {
  log_write 1 "$1"
  echo "$1" >&2
}

log_flags() {
  log_write 4 "  CPPFLAGS: \"$CPPFLAGS\""
  log_write 4 "  CFLAGS:   \"$CFLAGS\""
  log_write 4 "  CXXFLAGS: \"$CXXFLAGS\""
  log_write 4 "  LDFLAGS:  \"$LDFLAGS\""
  log_write 4 "  PATH:     \"$PATH\""
}

# Generate scripts which can be used to launch this compiling environment
#
# $1 - Target path
generate_setup_scripts() {
  log_write 1 "Writing setup scripts"

  if ! (
    echo "#"\!"/bin/sh"
    echo "export CROSSER=$TARGET"
    echo "export PATH=\"$PATH\""
    echo "export PS1=\"Crosser:> \""
    echo "hash -r"
    echo "/bin/bash --norc"
  ) > $1/setup.sh
  then
    log_error "Failed to create $1/setup.sh"
    return 1
  fi

  chmod a+x $1/setup.sh
}

# Apply patch to component
#
# $1 - Subdir in source hierarchy to patch
# $2 - Patch name
patch_src() {
  log_write 2 "Patching $1: $2.diff"

  if ! patch -u -p1 -d $MAINSRCDIR/$1 < $MAINDIR/patch/$2.diff \
       >> $MAINLOGDIR/stdout.log 2>> $MAINLOGDIR/stderr.log
  then
    log_error "Patching $1 with $2.diff failed"
    return 1
  fi
}

# Unpack component package to source directory
#
# $1   - Package name
# $2   - Package version
# [$3] - Subdir in source hierarchy
# [$4] - Package file name in case it cannot be determined automatically
unpack_component() {
  if test "x$DL_ON_DEMAND" = "xyes" ; then
    log_write 1 "Downloading $1 version $2"
    if ! $MAINPACKETDIR/download_packets.sh --packet "$1" "$2" \
         >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
    then
      log_error "Failed to download $1 version $2"
      return 1
    fi
  fi

  log_write 1 "Unpacking $1 version $2"

  if test "x$4" != "x" ; then
    # Custom file name format
    if ! tar xzf $MAINPACKETDIR/$4 -C $MAINSRCDIR/$3
    then
      log_error "Unpacking $4 failed"
    fi
  elif test -e $MAINPACKETDIR/$1-$2.tar.bz2 ; then
    if ! tar xjf $MAINPACKETDIR/$1-$2.tar.bz2 -C $MAINSRCDIR/$3
    then
      log_error "Unpacking $1-$2.tar.bz2 failed"
      return 1
    fi
  elif test -e $MAINPACKETDIR/$1-$2.tar.gz ; then
    if ! tar xzf $MAINPACKETDIR/$1-$2.tar.gz -C $MAINSRCDIR/$3
    then
      log_error "Unpacking $1-$2.tar.gz failed"
      return 1
    fi
  elif test -e $MAINPACKETDIR/${1}_${2}.dsc ; then
    if ! which dpkg-source >/dev/null ; then
      log_error "No way to unpack debian source packages"
      return 1
    fi
    if test "x$3" = "x" ; then
      SRCDIR="$1"
    else
      SRCDIR="$3"
    fi
    if ! dpkg-source -x $MAINPACKETDIR/${1}_${2}.dsc $MAINSRCDIR/$SRCDIR
    then
      log_error "Unpacking $1_$2.dsc failed"
      return 1
    fi
  else
    log_error "Can't find $1 version $2 package to unpack."
    return 1
  fi
}

# Output subdir under source hierarchy where component lives
#
# $1 -   Package
# $2 -   Version
src_subdir() {
  if test -d "$MAINSRCDIR/$1-$2"
  then
    echo "$1-$2"
  elif test -d "$MAINSRCDIR/$1"
  then
    echo "$1"
  else
    return 1
  fi
}

# Run set of autotools for component
#
# $1   - Package
# $2   - Version
# [$3] - List of tools to execute, "all" to force use of all tools
autogen_component()
{
  log_packet "autogen $1"

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  cd $MAINSRCDIR/$SUBDIR

  if test "x$3" = "x" && test -f autogen.sh ; then
    if ! test -x autogen.sh ; then
      log_write 1 "Making $1 autogen.sh executable"
      chmod u+x autogen.sh
    fi
    if ! ./autogen.sh ; then
      log_error "Autogen failed for $1"
      return 1
    fi
  else
    if test "x$3" = "x" || test "x$3" = "xall" ; then
      TOOLS="aclocal automake autoconf"
    else
      TOOLS="$3"
    fi
    for TOOL in $TOOLS
    do
      if ! $TOOL >>$MAINLOGDIR/stdout.log 2>>$MAINLOGDIR/stderr.log
      then
        log_error "Autotool $TOOL failed for $1 version $2"
        return 1
      fi
    done
  fi
}

# Outputs parsed prefix.
#
# $1   - Prefix to parse
setup_prefix() {
  echo $1 | sed -e "s/<TARGET>/$TARGET/g" \
                -e "s/<DATE>/$BUILD_DATE/g" \
                -e "s/<CLIB>/$LIBC_MODE/g"
}

# Outputs one parsed prefix. Can take one or two parameters and decides
# which one to parse.
#
# $1   - Default prefix to use if $2 missing
# [$2] - Prefix to parse
setup_prefix_default() {
  if test "x$2" != "x" ; then
    setup_prefix "$2"
  else
    setup_prefix "$1"
  fi
}

# Output tokenized version
#
# $1 - Version string
tokenize_version() {
  # Replace '.' and '-' with space.
  # Unify alpha and beta to lower case, make them separate tokens.
  # Make numbers appearing after letters separate token.
  echo $1 |
    sed -e 's/\./ /g' -e 's/-/ /g' \
        -e 's/[aA][lL][pP][hH][aA]/ alpha /g' \
        -e 's/[bB][eE][tT][aA]/ beta /g' \
        -e 's/\([^0-9]\)\([0-9]\)/\1 \2/g'
}

# Compare two version numbers
#
# $1 - First version
# $2 - Second version
#
# 0  - Versions equal
# 1  - $1 is greater than $2
# 2  - $2 is greater than $1
cmp_versions() {
  VER1PARTS="$(tokenize_version $1)"
  VER2PARTS="$(tokenize_version $2)"

  for PART1 in $VER1PARTS
  do
    # First remaining part of VER2PARTS
    PART2="$(echo $VER2PARTS | cut -f 1 -d ' ')"
    if test "x$PART2" = "x"
    then
      if test "x$PART1" = "xalpha" || test "x$PART1" = "xbeta"
      then
        # alpha and beta are less than pure version.
        return 2
      fi
      return 1
    fi
    if test "x$PART1" != "x$PART2"
    then
      if test "x$PART1" = "xalpha"
      then
        return 2
      fi
      if test "x$PART2" = "xalpha"
      then
        return 1
      fi
      if test "x$PART1" = "xbeta"
      then
        return 2
      fi
      if test "x$PART2" = "xbeta"
      then
        return 1
      fi
      PART1NBR="$(echo $PART1 | sed 's/[^0-9].*//')"
      PART2NBR="$(echo $PART2 | sed 's/[^0-9].*//')"
      if test 0$PART1NBR -gt 0$PART2NBR
      then
        return 1
      fi
      if test 0$PART2NBR -gt 0$PART1NBR
      then
        return 2
      fi
      PART1TEXT="$(echo $PART1 | sed 's/[0-9]*//')"
      PART2TEXT="$(echo $PART2 | sed 's/[0-9]*//')"
      SMALLERTEXT="$(( echo $PART1TEXT && echo $PART2TEXT ) | sort | head -n 1)"
      if test "x$PART2TEXT" = "x$SMALLERTEXT"
      then
        return 1
      fi
      return 2
    fi
    # Remove first, now handled, part of VER2PARTS
    VER2PARTS="$(echo $VER2PARTS | sed 's/[^ ]*//')"
  done

  if test "x$VER2PARTS" != "x"
  then
    PART2=$(echo $VER2PARTS | cut -f 1 -d " ")
    if test "x$PART2" = "xalpha" || test "x$PART2" = "xbeta"
    then
      # alpha and beta are less than pure version.
      return 1
    fi
    return 2
  fi

  return 0
}

# Check if version number is at least comparison version
#
# $1 - Version number
# $2 - Comparison version
is_minimum_version() {
  cmp_versions "$1" "$2"

  if test $? -eq 2
  then
    return 1
  fi
}

# Check if version number is at most comparison version
#
# $1 - Version number
# $2 - Comparison version
is_max_version() {
  cmp_versions "$1" "$2"

  if test $? -eq 1
  then
    return 1
  fi
}

# Check if version number is smaller than comparison version
#
# $1 - Version number
# $2 - Comparison version
is_smaller_version() {
  cmp_versions "$1" "$2"

  if test $? -ne 2
  then
    return 1
  fi
}

# Check if version number is greater than comparison version
#
# $1 - Version number
# $2 - Comparison version
is_greater_version() {
  cmp_versions "$1" "$2"

  if test $? -ne 1
  then
    return 1
  fi
}
