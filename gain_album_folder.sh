#!/bin/sh

FOLDER="$1"

echo "Processing album in $FOLDER"
find "$FOLDER" -iname '*.flac' -type f -exec loudgain -a -k -s e {} +
