#!/bin/bash

FIND_PATH="$1"
FILE_REGEX="$2"

find "$FIND_PATH" -iname "$FILE_REGEX" | while read -r fname
do
	fenc="$(uchardet "$fname")"
	[ "$fenc" = "UTF-8" ] && continue
	[ "$fenc" = "ASCII" ] && continue
	echo converting "$fname" from "$fenc" to UTF-8
	mv "$fname" "$fname.orig"
	iconv -f "$fenc" -t "UTF-8" -o "$fname" "$fname.orig"
done
