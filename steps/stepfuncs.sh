# No shebang. This file is meant to be sourced in.

# stepfuncs.sh: Functions handling Crosser steps.
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

STEP_native_PACKETS=$(cat $MAINDIR/steps/native.step)
STEP_chain_PACKETS=$(cat $MAINDIR/steps/chain.step)
STEP_win_PACKETS=$(cat $MAINDIR/steps/win.step)

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
