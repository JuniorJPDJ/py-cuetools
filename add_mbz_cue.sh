#!/bin/bash

[ -f "$1" ] || { echo "$1" does not exist ; exit 1 ; }
[ "${1##*.}" == "cue" ] || { echo "$1" is not .cue file ; exit 2 ; }

cue="$(grep -v 'REM MUSICBRAINZ_RELEASE ' "$1")"

cue_file_regexp='FILE \"(.*?)\" WAVE'
file="$(printf '%s\n' "$cue" | while read -r cueline ; do
	if [[ "$cueline" =~ $cue_file_regexp ]] ; then
		file="$(dirname "$1")/${BASH_REMATCH[1]}"
		[ -f "$file" ] && printf '%s' "$file" && break
	fi
done)"
[ -z "$file" ] && echo "No existing file found in $1" && exit 3

release_group="$(ffprobe "$file" 2>&1 | grep MUSICBRAINZ_ALBUMID | awk '{print $2}')"
[ -z "$release_group" ] && echo "$file doesn't contain MUSICBRAINZ_ALBUMID tag" && exit 4

#mv "$1" "$1.orig"
printf 'REM MUSICBRAINZ_RELEASE %s\n%s\n' "$release_group" "$cue" > "$1"
