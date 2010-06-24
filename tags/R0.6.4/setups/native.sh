#!/bin/sh

TMP_ALL="$($CROSSER_MAINDIR/scripts/aux/config.guess)"

TMP_ARCH=$(echo $TMP_ALL | cut -f 1 -d "-")
TMP_VENDOR=$(echo $TMP_ALL | cut -f 2 -d "-")
TMP_OS=$(echo $TMP_ALL | cut -f 3- -d "-")
