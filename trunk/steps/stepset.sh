# No shebang. This file must be sourced to actual script

# stepfuncs.sh: Functions handling Crosser steps.
#
# (c) 2008 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

for _STEP in $STEPLIST
do
  case $_STEP in
    native)
      STEP_NATIVE=yes ;;
    chain)
      STEP_CHAIN=yes ;;
    win)
      STEP_WIN=yes ;;
    sdl)
      STEP_SDL=yes ;;
    *)
      log_error "Unknown step $_STEP in stepset.sh" ;;
  esac
done
