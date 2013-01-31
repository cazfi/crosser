# No shebang, this script is not executed, but sourced.

# helpers.sh: Functions for Crosser
#
# (c) 2008-2012 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

if test "x$CROSSER_MAINDIR" = "x"
then
  echo "helpers.sh: Mandatory environments variables missing! Have you sourced proper settings already?" >&2
  exit 1
fi

if ! test -e "$CROSSER_MAINDIR/CrosserVersion"
then
  echo "helpers.sh: There seems to be problem with crosser installation." >&2
  echo "Looking data from $CROSSER_MAINDIR, but it's not there!" >&2
  exit 1
fi

CROSSER_VERSION=$(tail -n 1 "$CROSSER_MAINDIR/CrosserVersion")
BUILD_DATE=$(date +"%d.%m.%y")

if test "x$LOGLEVEL_STDOUT" = "x" ; then
  LOGLEVEL_STDOUT=2
fi
if test "x$LOGLEVEL_FILE" = "x" ; then
  LOGLEVEL_FILE=4
fi

if which cvercmp >/dev/null 2>&1 ; then
  CROSSER_CVERCMP=yes
fi

# Start new logfiles
#
log_init() {
  if ! mkdir -p "$CROSSER_LOGDIR"
  then
    echo "Failed to create logdir \"$CROSSER_LOGDIR\"" >&2
    return 1
  fi

  log_write 0 "== $(basename $0) $CROSSER_VERSION build starts =="
  rm -f "$CROSSER_LOGDIR/stderr.log"
  rm -f "$CROSSER_LOGDIR/stdout.log"
}

# Call this when starting build of new packet
#
# $1 - Packet name
log_packet() {
  # Create lines separating output from one packet build from the other
  echo "**** $1 ****" >> "$CROSSER_LOGDIR/stdout.log"
  echo "**** $1 ****" >> "$CROSSER_LOGDIR/stderr.log"
}

# Write message to logs
#
# $1 - Log level
# $2 - Message
log_write() {
  DSTAMP=$(date +"%d.%m %H:%M")

  if test "x$1" = "x0" ; then
    echo >> "$CROSSER_LOGDIR/main.log"
    log_write 1 "==========================================="
  fi

  if test $1 -le $LOGLEVEL_FILE
  then
    if test -f "$CROSSER_LOGDIR/main.log"
    then
      LOGSIZE=$(ls -l "$CROSSER_LOGDIR/main.log" | cut -f 5 -d " ")
      if test $LOGSIZE -gt 250000
      then
        mv "$CROSSER_LOGDIR/main.log" "$CROSSER_LOGDIR/main.old"
      fi
    fi
    echo -e "$DSTAMP $STEP:$STEPADD $2" >> "$CROSSER_LOGDIR/main.log"
  fi

  if test $1 -le $LOGLEVEL_STDOUT ; then
    echo -e "$DSTAMP $STEP:$STEPADD $2"
  fi
}

# Write error message to logs
#
# $1 - Error message
log_error() {
  log_write 1 "$1"
  echo "$1" >&2
}

# Write flag variables to logfile
#
log_flags() {
  log_write 4 "  CPPFLAGS: \"$CPPFLAGS\""
  log_write 4 "  CFLAGS:   \"$CFLAGS\""
  log_write 4 "  CXXFLAGS: \"$CXXFLAGS\""
  log_write 4 "  LDFLAGS:  \"$LDFLAGS\""
  log_write 4 "  PATH:     \"$PATH\""
}

# Apply patch to component
#
# $1 - Component name
# $2 - Component version
# $3 - Patch name
patch_src() {
  if test "x$2" = "x0"
  then
    return 0
  fi

  SRCSUBDIR="$(src_subdir $1 $2)"

  log_write 2 "Patching $SRCSUBDIR: $3.patch"

  if test -r "$CROSSER_MAINDIR/patch/$3.patch"
  then
    PATCH_NAME="$3.patch"
  elif test -r "$CROSSER_MAINDIR/patch/$3.diff"
  then
    PATCH_NAME="$3.diff"
  else
    log_error "No patch file $3.patch or $3.diff found."
    return 1
  fi

  if ! patch -u -p1 -d "$CROSSER_SRCDIR/$SRCSUBDIR" < "$CROSSER_MAINDIR/patch/$PATCH_NAME" \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Patching $SRCSUBDIR with $PATCH_NAME failed"
    return 1
  fi
}

# Apply upstream patch to component
#
# $1 - Subdir in source hierarchy to patch
# $2 - Patch name
upstream_patch() {
  log_write 2 "Patching $1: Upstream $2"

  if ! patch -p0 -d "$CROSSER_SRCDIR/$1" < "$PACKETDIR/patch/$2" \
       >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
  then
    log_error "Patching $1 with $2 failed"
    return 1
  fi
}

# Unpack component package to source directory
#
# $1   - Package name
# $2   - Package version, "0" to indicate that there is no package after all
# [$3] - Subdir in source hierarchy
# [$4] - Package file name base in case it's not 'name-version'
# [$5] - Number of patches
unpack_component() {
  if test "x$1" = "xgtk2" || test "x$1" = "xgtk3"
  then
    BNAME="gtk+"
  else
    BNAME="$1"
  fi

  if test "x$2" = "x0"
  then
    return 0
  fi

  if test "x$CROSSER_DOWNLOAD" = "xdemand"
  then
    log_write 1 "Fetching $BNAME version $2"
    if ! ( cd "$PACKETDIR" && "$CROSSER_MAINDIR/scripts/download_packets.sh" --packet "$1" "$2" "$5" \
         >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log" )
    then
      log_error "Failed to download $BNAME version $2"
      return 1
    fi
  fi

  log_write 1 "Unpacking $BNAME version $2"

  if test "x$4" != "x"
  then
    # Custom file name format
    NAME_BASE="$4"
  else
    NAME_BASE="$BNAME-$2"
  fi

  if test -e "$PACKETDIR/$NAME_BASE.tar.bz2" ; then
    if ! tar xjf "$PACKETDIR/$NAME_BASE.tar.bz2" -C "$CROSSER_SRCDIR/$3"
    then
      log_error "Unpacking $NAME_BASE.tar.bz2 failed"
      return 1
    fi
  elif test -e "$PACKETDIR/$NAME_BASE.tar.gz" ; then
    if ! tar xzf "$PACKETDIR/$NAME_BASE.tar.gz" -C "$CROSSER_SRCDIR/$3"
    then
      log_error "Unpacking $NAME_BASE.tar.gz failed"
      return 1
    fi
  elif test -e "$PACKETDIR/$NAME_BASE.tar.xz" ; then
    if ! tar xJf "$PACKETDIR/$NAME_BASE.tar.xz" -C "$CROSSER_SRCDIR/$3"
    then
      log_error "Unpacking $NAME_BASE.tar.xz failed"
      return 1
    fi
  elif test -e "$PACKETDIR/$NAME_BASE.tgz" ; then
    if ! tar xzf "$PACKETDIR/$NAME_BASE.tgz" -C "$CROSSER_SRCDIR/$3"
    then
      log_error "Unpacking $NAME_BASE.tgz failed"
      return 1
    fi
  elif test -e "$PACKETDIR/${BNAME}_${2}.dsc" ; then
    if ! which dpkg-source >/dev/null ; then
      log_error "No way to unpack debian source packages"
      return 1
    fi
    if test "x$3" = "x" ; then
      SRCDIR="$BNAME"
    else
      SRCDIR="$3"
    fi
    if ! dpkg-source -x "$PACKETDIR/${BNAME}_${2}.dsc" "$CROSSER_SRCDIR/$SRCDIR" \
                     >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
    then
      log_error "Unpacking $BNAME_$2.dsc failed"
      return 1
    fi
  else
    log_error "Can't find $BNAME version $2 package to unpack."
    return 1
  fi
}

# Free components temporary directories
#
# $1 -   Package
# $2 -   Version
# $3 -   Builddir
free_component() {
  free_src "$1" "$2"
  free_build "$3"
}

# Free components temporary source directory
#
# $1 -   Package
# $2 -   Version
free_src() {
  if test "x$CROSSER_TMPFREE" != "xyes"
  then
    return 0
  fi

  log_write 2 "Free source for $1 version $2"

  SRCSUBDIR=$(src_subdir $1 $2)
  if test "x$SRCSUBDIR" = "x"
  then
    echo "Cannot find srcdir of $1 version $2 to remove" >&2
    return 1
  fi

  rm -Rf "$CROSSER_SRCDIR/$SRCSUBDIR"
}

# Free components temporary build directory
#
# $1 -   Builddir
free_build() {
  if test "x$CROSSER_TMPFREE" != "xyes" 
  then
    return 0
  fi

  if test "x$1" = "x"
  then
    echo "No builddir given for free_build()" >&2
    return 1
  fi

  log_write 2 "Free builddir $1"

  if ! test -d "$CROSSER_BUILDDIR/$1"
  then
    echo "Cannot find builddir \"$CROSSER_BUILDDIR/$1\" to remove" >&2
    return 1
  fi

  rm -Rf "$CROSSER_BUILDDIR/$1"
}

# Output subdir under source hierarchy where component lives
#
# $1 -   Package
# $2 -   Version
src_subdir() {
  if test -d "$CROSSER_SRCDIR/$1-$2"
  then
    echo "$1-$2"
  elif test -d "$CROSSER_SRCDIR/$1"
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
# [$4] - Subdir under srcdir
autogen_component()
{
  if test "x$2" = "x0"
  then
    return 0
  fi

  log_packet "autogen $1"

  SUBDIR="$(src_subdir $1 $2)"

  if test "x$SUBDIR" = "x"
  then
    log_error "Cannot find srcdir for $1 version $2"
    return 1
  fi

  if ! test -d "$CROSSER_SRCDIR/$SUBDIR/$4"
  then
    log_error "No subdirectory $4 in $1 version $2 src directory"
    return 1
  fi

  cd "$CROSSER_SRCDIR/$SUBDIR/$4"

  if test "x$3" = "x" && test -f autogen.sh ; then
    if ! test -x autogen.sh ; then
      log_write 1 "Making $1 autogen.sh executable"
      chmod u+x autogen.sh
    fi
    if ! ./autogen.sh >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log" ; then
      log_error "Autogen failed for $1"
      return 1
    fi
  else
    if test "x$3" = "x" || test "x$3" = "xall" ; then
      TOOLS="aclocal autoheader automake autoconf"
    else
      TOOLS="$3"
    fi
    for TOOL in $TOOLS
    do
      if test "x$TOOL" = "xlibtoolize"
      then
        TOOLPARAM=" -f"
      elif test "x$TOOL" = "xautomake"
      then
        TOOLPARAM=" -a"
      elif test "x$TOOL" = "xaclocal"
      then
        if test -d m4
        then
          TOOLPARAM=" -I m4"
        else
          TOOLPARAM=""
        fi
        if test -d gnulib-m4
        then
          TOOLPARAM="$TOOLPARAM -I gnulib-m4"
        fi
        if test "x$4" != "x" && test -d "../m4"
        then
          TOOLPARAM="$TOOLPARAM -I ../m4"
        fi
      else
        TOOLPARAM=""
      fi

      if ! $TOOL$TOOLPARAM >> "$CROSSER_LOGDIR/stdout.log" 2>> "$CROSSER_LOGDIR/stderr.log"
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
                -e "s/<VERSION>/$CROSSER_VERSION/g" \
                -e "s/<VERSIONSET>/$VERSIONSET/g" \
                -e "s/<SETUP>/$SETUP/g"
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
  # Unify alpha,beta,pre,rc to lower case, make them separate tokens.
  # Check that 'rc' is not part of longer word before tokenizing.
  # Make numbers appearing after letters separate token.
  echo $1 |
    sed -e 's/\./ /g' -e 's/-/ /g' \
        -e 's/[aA][lL][pP][hH][aA]/ alpha /g' \
        -e 's/[bB][eE][tT][aA]/ beta /g' \
        -e 's/[pP][rR][eE]/ pre /g' \
        -e 's/[^alpha][rR][cC]/ rc /g' \
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
  if test "x$CROSSER_CVERCMP" = "xyes"
  then
    if cvercmp "$1" equal "$2" > /dev/null
    then
      return 0
    fi
    if cvercmp "$1" greater "$2" > /dev/null
    then
      return 1
    fi
    return 2
  fi

  VER1PARTS="$(tokenize_version $1)"
  VER2PARTS="$(tokenize_version $2)"

  for PART1 in $VER1PARTS
  do
    # First remaining part of VER2PARTS
    PART2="$(echo $VER2PARTS | cut -f 1 -d ' ')"
    if test "x$PART2" = "x"
    then
      if test "x$PART1" = "xalpha" || test "x$PART1" = "xbeta" ||
         test "x$PART1" = "xpre"   || test "x$PART1" = "xrc"
      then
        # alpha and beta are less than pure version.
        return 2
      fi
      return 1
    fi
    if test "x$PART1" != "x$PART2"
    then
      # Comparison between special version tokens.
      # We consider increasing order (latter is newer version) to be:
      #   alpha - beta - pre - rc
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
      if test "x$PART1" = "xpre"
      then
        return 2
      fi
      if test "x$PART2" = "xpre"
      then
        return 1
      fi
      if test "x$PART1" = "xrc"
      then
        return 2
      fi
      if test "x$PART2" = "xrc"
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
    if test "x$PART2" = "xalpha" || test "x$PART2" = "xbeta" ||
       test "x$PART2" = "xpre"   || test "x$PART2" = "xrc"
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
  if test "x$CROSSER_CVERCMP" = "xyes"
  then
    cvercmp "$1" min "$2" > /dev/null
    return $?
  fi

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
  if test "x$CROSSER_CVERCMP" = "xyes"
  then
    cvercmp "$1" max "$2" > /dev/null
    return $?
  fi

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
  if test "x$CROSSER_CVERCMP" = "xyes"
  then
    cvercmp "$1" lesser "$2" > /dev/null
    return $?
  fi

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
  if test "x$CROSSER_CVERCMP" = "xyes"
  then
    cvercmp "$1" greater "$2" > /dev/null
    return $?
  fi

  cmp_versions "$1" "$2"

  if test $? -ne 1
  then
    return 1
  fi
}

# Prompt yes/no question from user
#
# $1   - Question to ask, line 1
# [$2] - Question to ask, line 2 
#
# 0 - Answer was yes
# 1 - Answer was no
ask_yes_no() {
  ANSWER="unknown"

  while test "x$ANSWER" != "xyes" && test "x$ANSWER" != "xno"
  do
    echo "$1"
    if test "x$2" != "x"
    then
      echo "$2"
    fi
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
    return 1
  fi

  return 0
}

# Recursively deletes directory
#
# $1 - Directory path
#
# 0  - Directory no longer exist
# 1  - Directory still exist
remove_dir() {
  if ! test -d "$1"
  then
    # No such directory in the first place
    return 0
  fi

  log_write 3 "Directory \"$1\" exist already - needs to be removed"

  if test "x$CROSSER_FORCE" = "xno"
  then
    return 1
  fi

  if test "x$CROSSER_FORCE" != "xyes"
  then
    if ! ask_yes_no "Directory \"$1\" already exist." \
                    "Is it ok to delete that directory and all its contents?"
    then
      return 1
    fi
  fi

  if ! rm -Rf "$1"
  then
    return 1
  fi
}

# Prints configure variables for component with possible extra space in end
#
# $1 - Component
#
# 0 - Success
# 1 - Failure
read_configure_vars_sub() {
  CONF_FILE="$CROSSER_MAINDIR/setups/cachevars/$1.vars"

  if test -f "$CONF_FILE"
  then
    cat "$CONF_FILE" | ( while read CONDITION SEPARATOR REST
      do
        if test "x$SEPARATOR" != "x:"
        then
          log_error "Error in format of $CONF_FILE"
          return 1
        fi
        if echo "$TARGET" | grep $CONDITION > /dev/null
        then
          echo -n "$REST "
        fi
      done )
  fi

  return 0
}

# Prints configure variables for component
#
# $1 - Component
#
# 0 - Success
# 1 - Failure
read_configure_vars() {
  FULLTEXT="$(read_configure_vars_sub "$1")"

  if test "$?" = "1"
  then
    return 1
  fi

  echo "$FULLTEXT" | sed 's/ $//' 
}

# Check if packet directory exist and possibly create one
#
# 0 - Packetdir exist
# 1 - Packetdir missing
packetdir_check() {
  if ! test -d "$PACKETDIR/patch"
  then
    if test "x$CROSSER_FORCE" = "xno"
    then
      return 1
    fi

    if test "x$CROSSER_FORCE" != "xyes"
    then

      if ! ask_yes_no "Packet directory $PACKETDIR, or some subdirectory, missing. Create one?"
      then
        return 1
      fi
    fi

    if ! mkdir -p "$PACKETDIR/patch"
    then
      echo "Failed to create packet directory $PACKETDIR"
      return 1
    fi
  fi

  return 0
}
