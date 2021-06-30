#!/bin/sh

BASEDIR="$(dirname "$0")"

while IFS= read -rd $'\0' FOLDER; do
	[ "$FOLDER" = "$1" ] && continue
	
	"$BASEDIR/gain_album_folder.sh" "$FOLDER"
done < <(find "$1" -maxdepth 1 -type d -print0)

