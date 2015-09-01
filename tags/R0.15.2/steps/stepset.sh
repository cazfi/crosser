# No shebang. This file must be sourced to actual script

# stepfuncs.sh: Functions handling Crosser steps.
#
# (c) 2008-2012 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

for _STEP in $STEPLIST
do
  case $_STEP in
    win)
      STEP_WIN=yes ;;
    *)
      log_error "Unknown step $_STEP in stepset.sh" ;;
  esac
done
