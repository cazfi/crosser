# No shebang, this script is not executed, but sourced.

# native.sh: Get information of native environment
#
# (c) 2008-2010 Marko Lindqvist
#
# This program is licensed under Gnu General Public License version 2.

TMP_ALL="$($CROSSER_MAINDIR/scripts/aux/config.guess)"

TMP_ARCH=$(echo $TMP_ALL | cut -f 1 -d "-")
TMP_VENDOR=$(echo $TMP_ALL | cut -f 2 -d "-")
TMP_OS=$(echo $TMP_ALL | cut -f 3- -d "-")