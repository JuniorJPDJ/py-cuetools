#!/bin/sh

out="$("$(dirname "$0")/add_mbz_cue.sh" "$1")"
[ $? != 0 ] && kdialog --sorry "$out"
