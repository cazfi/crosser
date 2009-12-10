# No shebang. This file is meant to be sourced in.

# stepfuncs.sh: Functions handling Crosser steps.
#
# (c) 2008-2009 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

STEP_native_PACKETS=$(cat $MAINDIR/steps/native.step)
STEP_chain_PACKETS=$(cat $MAINDIR/steps/chain.step)
STEP_baselib_PACKETS=$(cat $MAINDIR/steps/baselib.step)
STEP_win_PACKETS=$(cat $MAINDIR/steps/win.step)
STEP_xorg_PACKETS=$(cat $MAINDIR/steps/xorg.step)
STEP_gtk_PACKETS=$(cat $MAINDIR/steps/gtk.step)
STEP_sdl_PACKETS=$(cat $MAINDIR/steps/sdl.step)
STEP_test_PACKETS=""

# Steps array
STEPLIST=("native" "chain" "baselib" "xorg" "gtk" "sdl" "test" "win")

# Check if packet belongs to step
#
# $1 - Packet
# $2 - Step
#
# 0 - Packet is part of the step
# 1 - Packet is not part of the step
belongs_to_step() {
  STEP_PACKETS="$(eval echo '$'STEP_${2}_PACKETS)"

  for PACKET in $STEP_PACKETS
  do
    if test "x$1" = "x$PACKET" ; then
      return 0
    fi
  done

  return 1
}

# Returns numeric id for step
#
# $1  - Step name
#
# 0   - Error
# 1-> - Step id
step2id() {
  declare -i SID=0

  while test $SID -lt ${#STEPLIST[@]}
  do
    if test "x$1" = "x${STEPLIST[$SID]}"
    then
      # Index + 1
      SID=$SID+1
      return $SID
    fi
    SID=$SID+1
  done

  return 0
}

# Outputs step name
#
# $1 - Step id
id2step() {
  declare -i INDEX=$1-1

  echo ${STEPLIST[$INDEX]}
}

# Outputs list of steps parsed from one BEGIN:END step range
#
# $1 - BEGIN:END pair or single step
#
# 0  - Ok
# 1  - Error
parse_stepparam() {
  echo $1 | sed 's/:/ /' |
  (
    read BEGIN_STEP END_STEP
    if test "x$END_STEP" != "x"
    then
      LIST_STEP=""
      step2id $BEGIN_STEP
      declare -i BID=$?
      step2id $END_STEP
      declare -i EID=$?
      if test "x$BID" = "x" || test "x$BID" = "x0" ||
         test "x$EID" = "x" || test "x$EID" = "x0"
      then
        return 1
      fi

      # Swap reversed parts. Could also consider this user error.
      if test $BID -gt $EID
      then
        TID=$EID
        EID=$BID
        BID=$TID
      fi

      while test $BID -le $EID
      do
        LIST_STEP="$LIST_STEP $(id2step $BID)"
        BID=$BID+1
      done
    elif test "x$BEGIN_STEP" = "xall"
    then
      declare -i BID=1
      while test $BID -le ${#STEPLIST[@]}
      do
        LIST_STEP="$LIST_STEP $(id2step $BID)"
        BID=$BID+1
      done
    else
      if step2id "$BEGIN_STEP"
      then
        return 1
      fi
      LIST_STEP="$BEGIN_STEP"
    fi

    echo $LIST_STEP
  )
}

# Outputs list of steps parsed from parameters
#
# $1 - Step parameters
#
# 0  - Ok
# 1  - Error
parse_steplist() {
  STEPS=""

  echo $1 | sed 's/,/ /g' |
  (
     read PARAMLIST 

     for PART in $PARAMLIST
     do
       STEP="$(parse_stepparam $PART)"
       RET=$?
       if test "x$RET" != "x0"
       then
         return 1
       fi
       STEPS="$STEPS $STEP"
     done

     echo $STEPS
  )
  RET=$?

  if test "x$RET" != "x0"
  then
    return 1
  fi
}
