#!/bin/bash
set -ex

# Files should first be tagged with Musicbrainz Picard

# This script expects folder tree like that:

# Main Music Directory (Library)
# |- Single CD Album
# |  |- Some additional file(s) (cover, cue sheet or anything additional)
# |  |- Track 01
# |  |- Track 02
# |  |- ...
# |
# |- Multi CD Album
# |  |- CD1 Folder
# |  |  |- Some additional file(s)
# |  |  |- Track 01
# |  |  |- Track 02
# |  |  |- ...
# |  |
# |  |- CD2 Folder
# |  |  |- ...
# |  |- ...
# |
# |- ...


function format_disc(){
	if [ "$tag_totaldiscs" -gt 1 ] ; then
		printf '%s' "CD${tag_disc}"
		[ -z "$tag_discsubtitle" ] || printf '%s' " - ${tag_discsubtitle}"
		printf '\n'
	fi
}

function format_album(){
	printf '%s\n' "${tag_originalyear}. ${tag_album_artist} - ${tag_album}"
}

function format_additional_file(){
	printf '%s' "00. ${tag_album_artist} - ${tag_album}"
	if [ "$tag_totaldiscs" -gt 1 ] ; then
		printf '%s' " - ${tag_media}${tag_disc}"
		[ -z "$tag_discsubtitle" ] || printf '%s' " - ${tag_discsubtitle}"
	fi
	printf '\n'
} 

function tags_to_vars(){
	file="$1"
	callback="$2"

	[ ! -f "$file" ] && return 1

	# import tags as local variables
	eval "$(ffprobe -v quiet -print_format json -show_format "$file" | jq -r '.format.tags | with_entries(.key |= (ascii_downcase | gsub("\\s+"; "_")))' | tail -n '+2' | head -n '-1' | sed -e 's/: /=/g' -e 's/,$//' -e 's/^  "/local "tag_/')"

	# run callback function in local scope
	eval "$callback"
}

function change_name(){
	in="$1"
	out="$2"
	pushd "$(dirname "$1")" > /dev/null
	mv "$(basename "$1")" "$out"
	popd > /dev/null
}

function interactive_rename(){
	in="$1"
	out="$2"
	read -p "Rename \"$in\" to \"$out\"? [Y/n/e]: " answer
	answer=${answer:-y}

	[ "$answer" = "n" ] && return
	[ "$answer" = "e" ] && answer="y" && read -ep "Rename \"$in\" to: " -i "$out" out || true
	[ "$answer" = "y" ] && change_name "$in" "$out" && return

	echo "Invalid answer."
	interactive_rename "$in" "$out"
}

function scoped(){
	# don't process the same directory more than once
	[ "$(dirname "$file")" = "$last_dir" ] && return || true
	last_dir="$(dirname "$file")"
	
	# additional files in the same directory
	new_name="$(format_additional_file)"
	while IFS= read -r -d $'\0' additional_file ; do {
		echo Found additional file: "$additional_file"
		fname="$(basename "$additional_file")"
		new_name_ext="$new_name.${fname##*.}"
		if [ -f "$additional_file" ] ; then
			[ "$fname" != "$new_name_ext" ] && interactive_rename "$additional_file" "$new_name_ext" || true 
		fi
	} <&3 ; done 3>&2 < <(find "$last_dir" -maxdepth 1 -type f -not \( -iname '*.flac' -or -iname '*.mp3' \) -print0)

	# rename disc dir if multidisc
	disc_new_name="$(format_disc)"
	[ "$disc_new_name" ] && [ "$(basename "$last_dir")" != "$disc_new_name" ] && interactive_rename "$last_dir" "$disc_new_name" || true

	# get album dir for single disc releases
	album_dir="$last_dir"
	# get album dir for multidisc releases
	[ "$disc_new_name" ] && album_dir="$(dirname "$album_dir")" || true

	album_new_name="$(format_album)"
	[ "$(basename "$album_dir")" != "$album_new_name" ] && interactive_rename "$album_dir" "$album_new_name" || true

	#echo Disc dir:
	#format_disc
	#echo Album dir:
	#format_album
	#echo Additional files base name:
	#format_additional_file
	#declare -p | grep "tag_"

	# TODO: Rename directories
}

function process_files(){
	dir="$1"
	while IFS= read -r -d $'\0' file ; do {
		tags_to_vars "$file" scoped
	} <&3 ; done 3>&2 < <(find "$dir" -type f -and \( -iname '*.flac' -or -iname '*.mp3' \) -and -print0)
}

#interactive_rename "$1" "$2"
#tags_to_vars "$1" scoped
process_files "$1"

